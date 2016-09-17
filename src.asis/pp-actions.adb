pragma Warnings (Off);
pragma Style_Checks (Off); -- ????
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Finalization;
with Ada.Strings.Fixed;
with System.WCh_Con;
with Text_IO, Ada.Wide_Text_IO; use Ada;
with Pp.Buffers; use Pp.Buffers;
with Pp.Formatting; use Pp.Formatting;
with Pp.Formatting.Dictionaries;
with Pp.Formatting.Tree_Formatting;
with Pp.Scanner;

with Ada.Containers.Generic_Constrained_Array_Sort;
with Ada.Directories; use Ada.Directories;
with Ada.Strings.Unbounded; use Ada;
with Ada.Characters.Handling;
with Interfaces; use type Interfaces.Unsigned_16;
with Unchecked_Deallocation;

with GNAT.Lock_Files;
with GNAT.OS_Lib; use GNAT.OS_Lib;

with Langkit_Support.Text; use Langkit_Support.Text;

with Libadalang;     use Libadalang;
with Libadalang.AST; use Libadalang.AST;
with Libadalang.Lexer;
with LAL_Extensions; use LAL_Extensions;

with LAL_UL.Common; use LAL_UL; use LAL_UL.Common;
with ASIS_UL.Dbg_Out;
with LAL_UL.Formatted_Output;
with ASIS_UL.String_Utilities; use ASIS_UL.String_Utilities;
with LAL_UL.Tool_Names;
with ASIS_UL.Char_Vectors; use ASIS_UL.Char_Vectors;
use ASIS_UL.Char_Vectors.Char_Vectors;
with ASIS_UL.Generic_Formatted_Output;

with ASIS_UL.Debug; use ASIS_UL.Debug;
with ASIS_UL.Vectors;

with LAL_UL.Projects;
with LAL_UL.Drivers;
with LAL_UL.Symbols; use LAL_UL.Symbols;
with LAL_UL.Environment;
with LAL_UL.Predefined_Symbols; use LAL_UL.Predefined_Symbols;
pragma Warnings (On);

package body Pp.Actions is

   function Image (X : Integer) return String
     renames ASIS_UL.String_Utilities.Image;

   pragma Warnings (Off);
   procedure Stop (Node : Ada_Node; S : W_Str);
   --  For setting breakpoints in gdb

   procedure Stop (Node : Ada_Node; S : W_Str) is
      P : constant Ada_Node_Array_Access := Parents (Node);
      use ASIS_UL.Dbg_Out;
   begin
      if False then
         Put ("Node:\n");
         Print (Node);
         if False then
            for X in P.Items'Range loop
               Put ("Parent \1:\n", Image (X));
               Print (P.Items (X));
            end loop;
         end if;
      end if;
   end Stop;

   procedure knd (X : Ada_Node);
   procedure nn (X : Ada_Node); -- was pp, but that conflicts with pkg name
   procedure ppp (X : Ada_Node);
   procedure Put_Ada_Node_Array (X : Ada_Node_Array);
   procedure Put_Child_Record (C : Child_Record);
   procedure Put_Children_Array (A : Children_Arrays.Array_Type);
   function Par (X : Ada_Node) return Ada_Node is (Parent (X));
   --  Debugging printouts

   --  For debugging:

   procedure Put_Ada_Templates;
   procedure Format_Debug_Output (Message : String);

   procedure knd (X : Ada_Node) is
      use ASIS_UL.Dbg_Out;
   begin
      Put ("\1\n", Kind (X)'Img);
   end knd;

   procedure nn (X : Ada_Node) is
      use ASIS_UL.Dbg_Out;
   begin
      ASIS_UL.Dbg_Out.Output_Enabled := True;
      Put ("\1\n", (if X = null then "null" else Short_Image (X)));
   end nn;

   procedure ppp (X : Ada_Node) is
      use ASIS_UL.Dbg_Out;
   begin
      nn (X);
      Print (X);
   end ppp;

   procedure Put_Ada_Node_Array (X : Ada_Node_Array) is
      use ASIS_UL.Dbg_Out;
   begin
      for N of X loop
         nn (N);
         Put ("----------------\n");
      end loop;
   end Put_Ada_Node_Array;
   pragma Warnings (On);

   procedure Put_Child_Record (C : Child_Record) is
      use ASIS_UL.Dbg_Out;
   begin
      case C.Kind is
         when Child =>
            Put ("Child: \1\n", Short_Image (C.Node));
         when Trivia =>
            Put ("Trivia: \1 ""\2"" \3\n",
                 C.Trivia.Kind'Img,
                 To_UTF8 (Text_To_W_Str (C.Trivia.Text.all)),
                 Slocs.Image (C.Trivia.Sloc_Range));
      end case;
   end Put_Child_Record;

   procedure Put_Children_Array (A : Children_Arrays.Array_Type) is
      use ASIS_UL.Dbg_Out;
   begin
      for I in A'Range loop
         Put ("\1: ", Image (I));
         Put_Child_Record (A (I));
      end loop;
   end Put_Children_Array;

   pragma Warnings (Off); -- ???
   use Common_Flag_Switches, Common_String_Switches,
     Common_String_Seq_Switches, Common_Nat_Switches;

   use Pp_Flag_Switches,
     Pp_Boolean_Switches,
     Attribute_Casing_Switches,
     Keyword_Casing_Switches,
     Name_Casing_Switches,
     Enum_Casing_Switches,
     Type_Casing_Switches,
     Number_Casing_Switches,
     Pragma_Casing_Switches,
     Pp_String_Switches,
     Pp_Nat_Switches,
     Pp_String_Seq_Switches;
   pragma Warnings (On);

   File_Name_File_Name : String_Access;
   --  There is a "file name file"; this is its name. ASIS_Processing writes
   --  the output to a temp file, and Finalize moves the temp file to the
   --  actual output file. The file name file is used to pass the names of the
   --  temp and output files from ASIS_Processing to Finalize (both subunits of
   --  ASIS_UL.Source_Table.Processing).
   --
   --  ASIS_Processing is called once for each file, and it writes two lines to
   --  the file name file: the name of the temp file, and then the name of the
   --  output file. Finalize reads pairs of lines from the file name file, and
   --  moves temp --> output.
   --
   --  The reason for passing information via a file is that in
   --  Incremental_Mode, ASIS_Processing and Finalize are running in two
   --  different processes; the inner processes do ASIS_Processing, and need
   --  to pass those file names back to the outer process. The builder is in
   --  between inner and outer, and doesn't know how to cooperate in this
   --  dance.
   --
   --  The reason for doing all the renames at the end (after all
   --  ASIS_Processing is done) is again Incremental_Mode, specifically
   --  Replace_Modes. We don't want to replace the original input with the
   --  output during ASIS_Processing, because that would change timestamps and
   --  confuse the builder.
   --
   --  In Incremental_Mode, the File_Name_File_Name is constructed in the outer
   --  invocation (in Initialize), and passed down to the inner invocations via
   --  the command-line switch --file-name-file=. --file-name-file is not
   --  documented for users; it is for internal use only. In other modes, it is
   --  constructed in Initialize.
   --
   --  We use the file name file even in non-Incremental_Mode, even though it's
   --  not really necessary, just for uniformity/simplicity.
   --
   --  In Replace_Modes, we optimize by not overwriting the output (i.e. the
   --  input) if it didn't change. This is especially important in
   --  Incremental_Mode, because of the way the builder works: it will invoke
   --  gnatpp (in Mimic_gcc mode) on something.adb, which will pretty-print
   --  something.ads. If something.ads didn't need pretty-printing, we don't
   --  want to change its timestamp, causing real (code-generating) builds to
   --  do unnecessary recompiles.

   function Mimic_gcc (Cmd : Command_Line) return Boolean is
      (Arg (Cmd, Outer_Dir) /= null);

--   pragma Style_Checks ("M85");

   ----------
   -- Init --
   ----------

   procedure Init (Tool : in out Pp_Tool; Cmd : Command_Line) is
      pragma Unreferenced (Tool);
      File_Name_File : Text_IO.File_Type;

   --  Start of processing for Init

   begin
      pragma Assert (Environment.Initial_Dir = Current_Directory);
      if Mimic_gcc (Cmd) then
         pragma Assert (False);
         pragma Assert (Directories.Exists (File_Name_File_Name.all),
                        File_Name_File_Name.all & " not found");
      else
         File_Name_File_Name := new String'
           (Directories.Compose (Environment.Tool_Temp_Dir.all, "file_names"));

         --  Create an empty file name file, so ASIS_Processing can append to
         --  it. (Small annoyance: the file is not actually empty; it contains
         --  a single blank line, and Finalize has to work around that.)

         Text_IO.Create (File_Name_File,
                         Name => File_Name_File_Name.all);
         Text_IO.Close (File_Name_File);

--         if Incremental_Mode then
--            Append (ASIS_UL.Environment.Extra_Inner_Pre_Args,
--                    String'("-asis-tool-args"));
--            Append (ASIS_UL.Environment.Extra_Inner_Post_Args,
--                    String'("-asis-tool-args"));
--            Append (Extra_Inner_Pre_Args,
--                    String'("--file-name-file=" & File_Name_File_Name.all));
--         end if;
      end if;
   end Init;

   -----------
   -- Final --
   -----------

   procedure Final (Tool : in out Pp_Tool; Cmd : Command_Line) is
      --  If this is the outer process of an incremental build, or it is a
      --  non-incremental build, we move all the temp files to the output files.
      --  We don't need any file locking here, because all the inner processes
      --  that were writing to the File_Name_File have finished.

      pragma Unreferenced (Tool);
      use Text_IO;
      File_Name_File : File_Type;
      Ignored : Boolean;
      Count : Natural := 0; -- number of files moved
   begin
      if not Mimic_gcc (Cmd)
      --  and then not Nothing_To_Do
      then
         Open (File_Name_File, In_File, Name => File_Name_File_Name.all);

         --  The File_Name_File contains an initial blank line, due to Text_IO
         --  weirdness, so we need to discard it.

         declare
            Discard : constant String := Get_Line (File_Name_File);
            pragma Unreferenced (Discard);
         begin
            null;
         end;

         --  Read pairs of lines from the file name file, and do the moves.

         while not End_Of_File (File_Name_File) loop
            Count := Count + 1;
            declare
               Temp_Output_Name : constant String := Get_Line (File_Name_File);
               Output_Name : constant String := Get_Line (File_Name_File);
            begin
               if False then
                  Put_Line ("mv " & Temp_Output_Name & " " & Output_Name);
               end if;
               Move_File (Old_Name => Temp_Output_Name, New_Name => Output_Name);
            end;
         end loop;

         Close (File_Name_File);

         if not Debug_Flag_N then
            GNAT.OS_Lib.Delete_File (File_Name_File_Name.all, Ignored);
            --  No point in complaining on failure
         end if;

--         if Incremental_Mode and then Count = 0 then
--            Put_Line ("files are up to date");
--         end if;
      end if;
   end Final;

   ---------------------
   -- Per_File_Action --
   ---------------------
   pragma Warnings (Off); -- ???

   type Output_Modes is
   --  Defines the where and how gnatpp places the result source.
     (Pipe,
      --  Sends the output into Stderr.
      Output,
      --  Creates the file with the name specified in 'o' option. If the
      --  file with the given name already exists, does not erase it and gives
      --  up.
      Output_Force,
      --  Creates the file with the name specified in 'o' option. If the
      --  file with the given name already exists, erases the old file and
      --  replaces it with the pretty-printed source.
      Replace,
      --  Replaces the argument source with the pretty-printed source. The
      --  original source is stored in the file <arg_source>.npp. If the file
      --  with such a name already exists, gnatpp gives up.
      Replace_Force,
      --  Replaces the argument source with the pretty-printed source. The
      --  original source is stored in the file <arg_source>.npp. If the file
      --  with such a name already exists, gnatpp overrides it.
      Replace_No_Backup,
      --  Replaces the argument source with the pretty-printed source. The
      --  original source is not stored in any back-up file.
      Default,
      --  Put the result source into <arg_source>.pp, overriding the existing
      --  file if any.
      Output_Directory);
      --  Put the result into <arg_source_simple_name> in directory Out_Dir.

   PP_Suffix : constant String := ".pp";
   NPP_Suffix : constant String := ".npp";
   --  The suffixes for the file names for default result and backup copy
   --  files.

   subtype Create_Modes is Output_Modes with
     Predicate => Create_Modes in Output | Output_Force;
   subtype Replace_Modes is Output_Modes with
     Predicate => Replace_Modes in Replace | Replace_Force | Replace_No_Backup;

   function Get_Output_Mode (Cmd : Command_Line) return Output_Modes;
   function Get_Output_Mode (Cmd : Command_Line) return Output_Modes is
      Result : Output_Modes := Default;
   begin
      if Arg (Cmd, Output_Directory) /= null then
         pragma Assert (Result = Default);
         Result := Output_Directory;
      end if;
      if Arg (Cmd, Pipe) then
         pragma Assert (Result = Default);
         Result := Pipe;
      end if;
      if Arg (Cmd, Replace) then
         pragma Assert (Result = Default);
         Result := Replace;
      end if;
      if Arg (Cmd, Replace_Force) then
         pragma Assert (Result = Default);
         Result := Replace_Force;
      end if;
      if Arg (Cmd, Replace_No_Backup) then
         pragma Assert (Result = Default);
         Result := Replace_No_Backup;
      end if;
      if Arg (Cmd, Output) /= null then
         pragma Assert (Result = Default);
         Result := Output;
      end if;
      if Arg (Cmd, Output_Force) /= null then
         pragma Assert (Result = Default);
         Result := Output_Force;
      end if;
      return Result;
   end Get_Output_Mode;

   ----------------

   function Is_Null (Tree : Ada_Node) return Boolean is (Tree = null);
   function T_Img (Tree : Ada_Node) return String is (Short_Image (Tree));

   package Lines_Data_Pkg is new Generic_Lines_Data
     (Ada_Node, Cmd_Error_No_Tool_Name);
   use Lines_Data_Pkg;
   use Line_Break_Vectors;
   use Tab_Vectors, Tab_In_Line_Vectors, Tab_In_Line_Vector_Vectors;
   Lines_Data : Lines_Data_Rec;

   Out_Buf : Buffer renames Lines_Data.Out_Buf;
   Cur_Indentation : Natural renames Lines_Data.Cur_Indentation;
   Next_Line_Break_Unique_Id : Modular
       renames Lines_Data.Next_Line_Break_Unique_Id;
   All_Line_Breaks : Line_Break_Vector renames Lines_Data.All_Line_Breaks;
   Tabs : Tab_Vector renames Lines_Data.Tabs;
   Src_Tokens : Scanner.Token_Vector renames Lines_Data.Src_Tokens;
   Pp_Off_On_Delimiters : Scanner.Pp_Off_On_Delimiters_Rec
       renames Lines_Data.Pp_Off_On_Delimiters;
   Check_Whitespace : Boolean renames Lines_Data.Check_Whitespace;

   procedure Format_Debug_Output (Message : String) is
   begin
      Format_Debug_Output (Lines_Data, Message);
   end Format_Debug_Output;

   procedure Tree_To_Ada_2
     (Root      : Ada_Node;
      Src_Buf, Out_Buf   : in out Buffer;
      Cmd       : LAL_UL.Command_Lines.Command_Line;
      Is_PP : Boolean);

   --  Hard and soft line breaks:
   --
   --  A hard line break means a new-line WILL appear in the final output. A
   --  soft line break is a place where a new-line CAN appear; it will appear
   --  only if necessary to make lines short enough. Soft line breaks are
   --  prioritized: if there are several soft line breaks that can be used
   --  to shorten a given line, higher priority ones are chosen over lower
   --  priority ones. Normally, less nested ones are higher priority than
   --  more nested ones.

   type Ada_Template is new W_Str;
   --  This is similar to Formatted_Output.Template, except instead of
   --  inserting strings into the template, it inserts subtrees. See
   --  Interpret_Template in the subunit Tree_To_Ada. The special
   --  characters are:
   --
   --      $ -- insert a hard line break
   --      % -- same as $, but doesn't affect comment indentation
   --           (see Line_Break.Affects_Comments)
   --      { -- indent
   --      } -- outdent
   --      @ -- insert a soft line break. May be followed by 1, 2, etc,
   --           to indicate additional nesting depth.
   --      [ -- continuation-line indent
   --      ] -- continuation-line outdent
   --      ( -- insert a "(", and add "extra" indent by 1 character
   --      ) -- insert a ")", and outdent the "extra"
   --      ^ -- tab based on following token. May be followed by 1, 2, etc,
   --           to indicate Index_In_Line.
   --      & -- insertion point for next "^" tab.
   --      ! -- insert next required subtree
   --      ? -- insert next optional or list subtree
   --      ~ -- delimits arguments of ?
   --      !1, !2, !3, etc -- insert N'th required subtree
   --      ?1, ?2, ?3, etc -- insert N'th optional or list subtree
   --      / -- ignore next required subtree
   --  Other characters are inserted verbatim.
   --
   --  All subtrees are required to be "used". If you don't want any output for
   --  a given subtree, then use / to ignore that subtree. Thus, all subtrees
   --  should be mentioned by one of: ! ? /.
   --
   --  ? takes three arguments, delimited by ~. If the subtree is a list, the
   --  first argument is placed before the list, the second in between list
   --  elements, and the third after the list, except if the list is empty,
   --  nothing is printed. If it's not a list, the first and third arguments
   --  are placed before and after, and the second must be empty, except if
   --  it's Not_An_Element, nothing is printed.
   --
   --  Normally, the soft line breaks inserted by @ have a priority based on
   --  the syntactic nesting depth. Less-nested breaks are enabled in favor of
   --  more deeply nested ones. However, if @ is followed by a digit, that
   --  indicates an additional nesting depth not reflected in the syntax. For
   --  example, if we have "blah @blah @1blah", then the @1 is considered more
   --  nested than the @, so if the line is too long, we first enable the @,
   --  and only enable the @1 if the line is still too long.
   --
   --  Examples:
   --  "!X!X!" -- inserts three subtrees, with "X" in between. "!1X!2X!3" --
   --  same as "!X!X!"
   --
   --  "?(~,~)~" -- a parenthesized comma-separated list
   --
   --  There is no way to escape the special characters, so for example, you
   --  can't print a literal $. So far, that wasn't needed, because those
   --  characters were deliberately chosen not to be part of Ada syntax. They
   --  can of course appear inside string literals and comments, but they're
   --  not needed in the templates.
   --
   --  Pairs of {}, [], and () must match and be properly nested.
   --
   --  The extra indentation for "(" is needed for parenthesized syntax, like
   --  this:
   --
   --      Do_Something
   --        (This,
   --         That);
   --        ^
   --        | Extra blank needed there.
   --
   --  Note: If you want to add new special characters, look at the case
   --  statement in Interpret_Template.

   type Ada_Template_Ptr is access Ada_Template;

   function Handled_Seq (Name_Subtree : Ada_Template) return Ada_Template;
   --  Template for a handled_sequence_of_statements. Name_Subtree is the index
   --  of the subtree that is the defining name, which is used to insert that
   --  name after "end", as in "end Package_Name;".

   --  ???Use some renamings for now, to ease the transition from ASIS to
   --  libadalang:
   subtype Ada_Tree_Kind is Ada_Node_Kind_Type;
   subtype Opt_ASIS_Elems is Ada_Node_Kind_Type;
   subtype Flat_Attribute_Reference_Kinds is Ada_Node_Kind_Type;
   subtype Flat_Pragma_Kinds is Ada_Node_Kind_Type;
   subtype Query_Index is Positive;
   subtype Query_Count is Natural;
   subtype Ada_Tree_Base is Ada_Node;
   subtype Ada_Tree is Ada_Node;
   subtype Ada_Tree_Array is Ada_Node_Arrays.Array_Type;
   function Is_Nil (T : Ada_Node) return Boolean is (T = null);
   function Subtree_Count (T : Ada_Tree) return Query_Count is
     (if T = null then 0 else Last_Child_Index (T));
   function Empty_Tree_Array return Ada_Node_Arrays.Array_Type is
     ((1 .. 0 => <>));
   function Subtrees (T : Ada_Tree) return Ada_Tree_Array is
     (if T = null then Empty_Tree_Array else Children (T));
   function Subtree (T : Ada_Tree; X : Query_Index) return Ada_Tree is
     (Child (T, X));

   function Template_For_Kind (Kind : Ada_Tree_Kind) return Ada_Template_Ptr;

   function L (T1 : Ada_Template) return Ada_Template_Ptr;
   function L (T1, T2 : Ada_Template) return Ada_Template_Ptr;
   function L (T1, T2, T3 : Ada_Template) return Ada_Template_Ptr;
   function L (T1, T2, T3, T4 : Ada_Template) return Ada_Template_Ptr;
   function L (T1, T2, T3, T4, T5 : Ada_Template) return Ada_Template_Ptr;
   function L (T1, T2, T3, T4, T5, T6 : Ada_Template) return Ada_Template_Ptr;
   function L
     (T1, T2, T3, T4, T5, T6, T7 : Ada_Template)
      return                       Ada_Template_Ptr;
   --  8-parameter version not needed so far
   function L
     (T1, T2, T3, T4, T5, T6, T7, T8, T9 : Ada_Template)
      return                               Ada_Template_Ptr;
   --  All the L functions form a template by concatenating together a bunch of
   --  lines.

   function Handled_Seq (Name_Subtree : Ada_Template) return Ada_Template is
   begin
      return "?begin$" &
        "{~;$~;$}~" &
        "?exception$" &
        "{~$~}~" &
        "end?" &
        Name_Subtree &
        " ~~~";
      --  The name after "end" is optional; it is often missing for
      --  block_statements, for example.
   end Handled_Seq;

   Handled_Seq_1 : constant Ada_Template := Handled_Seq ("1");
   Handled_Seq_2 : constant Ada_Template := Handled_Seq ("2");
   Handled_Seq_3 : constant Ada_Template := Handled_Seq ("3");

   Aspects : constant Ada_Template := "? with$" & "{~,$~}~";
   --  ???We could try something like the following: return "? with[@1 ~,@1
   --  ~]~";

   Labels : constant Ada_Template := "?<<~>> <<~>>$~";

   Ret_Typ : constant Ada_Template := "[@1 return? ~~~ !]";

   function L (T1 : Ada_Template) return Ada_Template_Ptr is
   begin
      return new Ada_Template'(T1);
   end L;

   function L (T1, T2 : Ada_Template) return Ada_Template_Ptr is
   begin
      return new Ada_Template'(T1 & T2);
   end L;

   function L (T1, T2, T3 : Ada_Template) return Ada_Template_Ptr is
   begin
      return new Ada_Template'(T1 & T2 & T3);
   end L;

   function L (T1, T2, T3, T4 : Ada_Template) return Ada_Template_Ptr is
   begin
      return new Ada_Template'(T1 & T2 & T3 & T4);
   end L;

   function L (T1, T2, T3, T4, T5 : Ada_Template) return Ada_Template_Ptr is
   begin
      return new Ada_Template'(T1 & T2 & T3 & T4 & T5);
   end L;

   function L
     (T1, T2, T3, T4, T5, T6 : Ada_Template)
      return                   Ada_Template_Ptr
   is
   begin
      return new Ada_Template'(T1 & T2 & T3 & T4 & T5 & T6);
   end L;

   function L
     (T1, T2, T3, T4, T5, T6, T7 : Ada_Template)
      return                       Ada_Template_Ptr
   is
   begin
      return new Ada_Template'(T1 & T2 & T3 & T4 & T5 & T6 & T7);
   end L;

   function L
     (T1, T2, T3, T4, T5, T6, T7, T8, T9 : Ada_Template)
      return                               Ada_Template_Ptr
   is
   begin
      return new Ada_Template'(T1 & T2 & T3 & T4 & T5 & T6 & T7 & T8 & T9);
   end L;

   function Template_For_Kind (Kind : Ada_Tree_Kind) return Ada_Template_Ptr is
   begin
      return
        (case Kind is
           when Ada_Library_Item =>
             L ("!"), -- misses "private"
           when Ada_Package_Decl =>
--             L ("package ![@",
--                Aspects,
--                "]@ is$",
--                "?${~;$~};$~",
--                "?$private$",
--                "{~;$~};$~",
--                "end !1"),
             L ("package ![@",
                Aspects,
                "]@ is$",
                "!",
                "?$private$",
                "{~~}~",
                "end !1/"),
           when Ada_Public_Part | Ada_Private_Part =>
             L ("?{~;$~};$~"),
           when others => null);
   end Template_For_Kind;

   type Template_Table_Type is array (Ada_Tree_Kind) of Ada_Template_Ptr;

   Template_Table             : Template_Table_Type;
   Template_Table_Initialized : Boolean := False;

   procedure Tree_To_Ada_2
     (Root      : Ada_Node;
      Src_Buf, Out_Buf   : in out Buffer;
      Cmd       : LAL_UL.Command_Lines.Command_Line;
      Is_PP : Boolean)
   is

      procedure Put_To_Buffer (C : W_Char);
      --  Append C to Buffer

      procedure Init_Template_Table;
      --  We call this to initialize Template_Table the first time Tree_To_Ada
      --  is called, so that we can base the initialization in part on the
      --  command-line options.

      procedure Init_Pp_Off_And_On;
      --  Initialize Pp_Off_On_Delimiters

      procedure Assert_No_Trailing_Blanks (S : W_Str);
      --  Assert that there are no lines with trailing blanks in S.

      function Id_With_Casing
        (Id                       : Symbol;
         Kind                     : Opt_ASIS_Elems;
         Is_Predef                : Boolean;
         Use_Name_Casing_For_Nils : Boolean := False)
         return                     W_Str;
      --  This handles casing of defining names and usage names, converting to
      --  the appropriate case based on command-line options. Kind is the kind of
      --  declaration denoted by Id, or an attribute, or nil. Is_Predef is True if
      --  Id denotes a predefined Ada or GNAT identifier.
      --
      --  This is called early (during Subtree_To_Ada). Casing of reserved words
      --  is handled later, in a separate pass (see Keyword_Casing), because they
      --  are not explicit in the tree, except that operator symbols are handled
      --  here. All of the Ada_Templates have reserved words in lower case.
      --
      --  Id_With_Casing is used for Def_Names, Usage_Names and pragmas. For
      --  Def_Names, the Kind comes from the Symbol_Table, which only works
      --  because it's within one unit. That doesn't work for Usage_Names; we
      --  use the Decl_Kind attribute, which includes declared entities and
      --  attributes. For pragmas, we use the Kind of the pragma node.
      --
      --  Is_Predef comes from the Is_Predef attribute of Usage_Names. It is
      --  always False for Def_Names and pragmas.
      --
      --  Use_Name_Casing_For_Nils is documented in Do_Usage_Name.

      function Init_Use_Dictionary return Boolean;
      function Init_Use_Dictionary return Boolean is
      begin
         for D_Name of Arg (Cmd, Dictionary) loop
            if D_Name.all /= "-" then
               return True;
            end if;
         end loop;
         return False;
      end Init_Use_Dictionary;

      Use_Dictionary : constant Boolean := Init_Use_Dictionary;
      --  True if there are any dictionary files to use

      function Init_Use_Predefined_Casing return Boolean;
      function Init_Use_Predefined_Casing return Boolean is
      begin
         for D_Name of Arg (Cmd, Dictionary) loop
            if D_Name.all = "-" then
               return False;
            end if;
         end loop;
         return True;
      end Init_Use_Predefined_Casing;

      Use_Predefined_Casing : constant Boolean := Init_Use_Predefined_Casing;
      --  True if the -D- switch was NOT given

      type Out_File_Formats is (CRLF, LF);

      function Get_Out_File_Format return Out_File_Formats;
      --  This function is supposed to be used as a part of tool parameters
      --  processing. It tries to convert its parameter into the corresponding
      --  value of Out_File_Formats type using the following conventions:
      --
      --    "dos"     -> CRLF
      --    "crlf"    -> CRLF
      --    "unix"    -> LF
      --     "lf"     -> LF
      --
      --  Generates the error message and raises Parameter_Error if such a
      --  conversion is not possible.

      function Get_Out_File_Format return Out_File_Formats is
         Is_Windows : constant Boolean := GNAT.OS_Lib.Directory_Separator = '\';
         Val : constant String_Ref := Arg (Cmd, End_Of_Line);
      begin
         if Val = null then
            return (if Is_Windows then CRLF else LF);
         elsif Val.all = "dos" or else Val.all = "crlf" then
            return CRLF;
         elsif Val.all = "unix" or else Val.all = "lf" then
            return LF;
         else
            raise Program_Error; -- Should have been validated earlier.
   --         Error ("Unrecognized output file format " & Val.all);
   --         raise Parameter_Error;
         end if;
      end Get_Out_File_Format;

      Out_File_Format : constant Out_File_Formats := Get_Out_File_Format;
      --  Format of the tool report file(s)

      procedure Put_To_Buffer (C : W_Char) is
      begin
         pragma Assert
           (if
              Check_Whitespace and then Arg (Cmd, Par_Threshold) = Natural'Last
            then
              (if C = ' ' then Lookback (Out_Buf) /= ' '));
         --  No double blanks. Except that there is one special case when the
         --  Par_Specs_Threshold switch is used, where we have an extra blank
         --  (see Subp_Decl_With_Hard_Breaks).
         pragma Assert (if C = NL then Lookback (Out_Buf) /= ' ');
         --  no trailing blanks

         Append_Any (Out_Buf, C);
         if False then
            String_Utilities.Wide_Text_IO_Put_Char (C);
         end if;
      end Put_To_Buffer;

      Name_CPP_Class : aliased constant W_Str := "CPP_Class";
      Name_CPP_Constructor : aliased constant W_Str := "CPP_Constructor";
      Name_CPP_Virtual : aliased constant W_Str := "CPP_Virtual";
      Name_CPP_Vtable  : aliased constant W_Str := "CPP_Vtable ";
      Name_CPU : aliased constant W_Str := "CPU";
      Name_Persistent_BSS : aliased constant W_Str := "Persistent_BSS";
      Name_SPARK_Mode : aliased constant W_Str := "SPARK_Mode";
      Name_Use_VADS_Size : aliased constant W_Str := "Use_VADS_Size";
      Name_VADS_Size : aliased constant W_Str := "VADS_size";

      Special_Case_Names : constant
          array (Positive range <>) of access constant W_Str :=
        (Name_CPP_Class'Access,
         Name_CPP_Constructor'Access,
         Name_CPP_Virtual'Access,
         Name_CPP_Vtable 'Access,
         Name_CPU'Access,
         Name_Persistent_BSS'Access,
         Name_SPARK_Mode'Access,
         Name_Use_VADS_Size'Access,
         Name_VADS_Size'Access);

      function Id_With_Casing
        (Id                       : Symbol;
         Kind                     : Opt_ASIS_Elems;
         Is_Predef                : Boolean;
         Use_Name_Casing_For_Nils : Boolean := False)
         return                     W_Str
      is

         Str : W_Str := To_W_Str (Id);
         --  This is the name as declared
         pragma Assert (Str'First = 1);

         --  If it's a character literal, we want As_Declared -- it would be
         --  unfortunate to turn 'a' into 'A'. Operators go by keyword casing.
         --  Operator symbols (quoted) do so also, which seems wrong, but we're
         --  going to mimic the old gnatpp for now. Note that some reserved
         --  words can be an operator or an attribute name; hence the check
         --  for Flat_Attribute_Reference_Kinds below. Predefined names use
         --  As_Declared unless Use_Predefined_Casing is turned off. For
         --  everything else, we use the appropriate option based on the Kind.

         Casing : constant PP_Casing :=
           (if Str (1) = ''' then As_Declared
            elsif
              Kind not in Flat_Attribute_Reference_Kinds
              and then
              (Str (1) = '"' -- operator symbol
               or else Is_Reserved_Word (Id, LAL_UL.Ada_Version)
               or else Id = Name_And_Then
               or else Id = Name_Or_Else)
            then
              PP_Keyword_Casing (Cmd)
            elsif
              Is_Predef and then Use_Predefined_Casing
            then
              As_Declared
            else
              (case Kind is
--                 when Flat_Attribute_Reference_Kinds =>
--                   PP_Attribute_Casing (Cmd),
--                 when Flat_Pragma_Kinds => PP_Pragma_Casing (Cmd),
--                 when An_Enumeration_Literal_Specification =>
--                   PP_Enum_Casing (Cmd),
--                 when A_Flat_Type_Declaration |
--                   A_Subtype_Declaration |
--                   A_Formal_Type_Declaration |
--                   A_Formal_Incomplete_Type_Declaration |
--                   A_Task_Body_Declaration |
--                   A_Protected_Body_Declaration =>
--                   PP_Type_Casing (Cmd),
--                 when A_Flat_Number_Declaration => PP_Number_Casing (Cmd),
--                 when Not_An_Element            =>
--                   (if Is_PP
--                      and then not Use_Name_Casing_For_Nils
--                      and then PP_Name_Casing (Cmd) = As_Declared
--                    then
--                      Mixed
--                    else PP_Name_Casing (Cmd)),
                 when others => PP_Name_Casing (Cmd)));
         --  The Not_An_Element case is for identifiers specific to pragmas
         --  and the like. But that only works if the Decl_Kind field is set,
         --  which isn't true in xml2gnat, so we use PP_Name_Casing (which is
         --  As_Declared) in that case.

         use Pp.Formatting.Dictionaries;
      begin
         if Use_Dictionary then
            Check_With_Dictionary (Ada_Name => Str, Casing => Casing);
            return Str;
         else
            case Casing is
               when Lower_Case =>
                  return To_Lower (Str);

               when Upper_Case =>
                  return To_Upper (Str);

               when Mixed =>
                  if Kind in Flat_Attribute_Reference_Kinds | Flat_Pragma_Kinds
                  then
                     --  Handle pragma and attribute names that are special cases
                     --  (some portion should be in ALL CAPS).

                     declare
                        Lower : constant W_Str := To_Lower (Str);
                     begin
                        for Special of Special_Case_Names loop
                           if Lower = To_Lower (Special.all) then
                              return Special.all;
                           end if;
                        end loop;
                     end;
                  end if;

                  return Capitalize (Str);

               when As_Declared =>
                  return Str;
            end case;
         end if;
      end Id_With_Casing;

      package Buffered_Output is new ASIS_UL.Generic_Formatted_Output
        (W_Char,
         W_Str,
         Basic_Put_Char => Put_To_Buffer);

      procedure Indent (Amount : Integer);

      procedure Indent (Amount : Integer) is
         pragma Assert
           (abs (Amount) in
              0 |
                1 |
                PP_Indentation (Cmd) |
                PP_Indent_Continuation (Cmd));
         Line_Breaks : Line_Break_Vector renames All_Line_Breaks;
      begin
         Cur_Indentation := Cur_Indentation + Amount;

         if abs (Amount) = PP_Indentation (Cmd) then
            pragma Assert (Point (Out_Buf) = Last_Position (Out_Buf) + 1);
            if Last_Position (Out_Buf) =
              Position (Out_Buf, Line_Breaks (Last (Line_Breaks)).Mark)
            then
   --  pragma Assert (At_Point (Out_Buf, Line_Breaks (Last (Line_Breaks)).Mark));
               Line_Breaks (Last (Line_Breaks)).Indentation := Cur_Indentation;
            end if;
         end if;
      end Indent;

      procedure Append_Line_Break
        (Hard     : Boolean;
         Affects_Comments : Boolean;
         Level    : Nesting_Level;
         Kind     : Ada_Tree_Kind;
         Template : Symbol);

      function Max_Nesting_Increment (Temp : Ada_Template) return Nesting_Level;
      --  If a digit occurs after '@', this is an additional "nesting increment"
      --  to be added to the nesting level when we recursively process the
      --  subtree. This is intended to allow some line breaks to have precedence
      --  over others. If no such digit occurs, the default is zero. This function
      --  returns the maximum such nesting increment in the template.

      function New_Level
        (Tree          : Ada_Tree;
         Subtree_Index : Query_Index;
         Cur_Level     : Nesting_Level;
         Temp          : Ada_Template)
         return          Nesting_Level;
      --  Compute a new nesting level for a subtree. This is usually one more than
      --  the current level, but we also add in Max_Nesting_Increment.

      procedure If_Statement_Check_1;
      procedure If_Statement_Check_2 (Level_Of_If : Nesting_Level);
      --  The above are for a special check related to if_statements, which comes
      --  in two parts. If_Statement_Check_1 and _2 are called before and after
      --  calling Subtree_To_Ada on the condition of an 'if'.
      --
      --  The compiler style checks complain if "then" appears by itself on the
      --  line immediately following "if" (still true???), as in:
      --     if <condition>
      --     then
      --  where <condition> is just long enough to split the line before "then",
      --  but not long enough to be split itself. To avoid that, we make sure
      --  at least one line break in <condition> is at the same level as the one
      --  just before "then", thus ensuring that if the latter is enabled, some
      --  line break within <condition> will also be enabled. The same goes for
      --  "elsif".
      --
      --  Part _1 remembers the index of the first line break for the condition.
      --  Then the condition is walked, possibly inserting some line breaks. Part
      --  _2 then finds the minimum nested level (i.e. outermost), and patches
      --  that to equal the level of the 'if'. If there are no line breaks in the
      --  condition, but it is still long enough to force the "then" onto the next
      --  line, then there's not much we can do -- the style check will fail in
      --  that unlikely case.

      procedure Append_Line_Break
        (Hard     : Boolean;
         Affects_Comments : Boolean;
         Level    : Nesting_Level;
         Kind     : Ada_Tree_Kind;
         Template : Symbol)
      is
         pragma Unreferenced (Kind);
         Line_Breaks : Line_Break_Vector renames All_Line_Breaks;
      begin
         --  If we see two line breaks in a row, we take the least indented one.

         if Hard and then Lookback (Out_Buf) = NL then
            if Line_Breaks (Last_Index (Line_Breaks)).Indentation >
              Cur_Indentation
            then
               Line_Breaks (Last_Index (Line_Breaks)).Indentation :=
                 Cur_Indentation;
            end if;

            if not Insert_Blank_Lines (Cmd) then
               return;
            end if;
         end if;

         Append
           (Line_Breaks,
            Line_Break'
              (Mark        => Mark (Out_Buf, Name => (if Hard then '$' else '@')),
               Hard        => Hard,
               Affects_Comments => Affects_Comments,
               Enabled     => Hard,
               Level       => Level,
               Indentation => Cur_Indentation,
               Length      => <>,
   --            Kind        => Kind,
               Template    => Template,
               UID         => Next_Line_Break_Unique_Id));
         Next_Line_Break_Unique_Id := Next_Line_Break_Unique_Id + 1;

         --  A hard line break gets NL

         if Hard then
            Buffered_Output.Put_Char (NL);
         end if;
      end Append_Line_Break;

      function Max_Nesting_Increment (Temp : Ada_Template) return Nesting_Level is
         J : Positive := Temp'First;
         C : W_Char;

      begin
         return Result : Nesting_Level := 0 do
            while J <= Temp'Last loop
               C := Temp (J);

               case C is
                  when '@' =>
                     declare
                        Digit     : W_Char;
                        Increment : Nesting_Level;

                     begin
                        if J < Temp'Last and then Temp (J + 1) in '0' .. '9' then
                           J         := J + 1;
                           Digit     := Temp (J);
                           Increment := Nesting_Level (Char_To_Digit (Digit));

                        else
                           Increment := 0;
                        end if;

                        Result := Nesting_Level'Max (Result, Increment);
                     end;

                  when others =>
                     null;
               end case;

               J := J + 1;
            end loop;
         end return;
      end Max_Nesting_Increment;

      function New_Level
        (Tree          : Ada_Tree;
         Subtree_Index : Query_Index;
         Cur_Level     : Nesting_Level;
         Temp          : Ada_Template)
         return          Nesting_Level
      is
      begin
--         pragma Assert
--           (if Tree.Kind in An_If_Path | An_Elsif_Path then Subtree_Index = 1);

         return Cur_Level + Max_Nesting_Increment (Temp) + 1;
      end New_Level;

      First_If_Line_Break : Line_Break_Index;
      --  Valid only between calls to If_Statement_Check_1 and
      --  If_Statement_Check_2. Set by _1 to 1 past the end of the table, which
      --  is where the next line break will be placed. Used by _2 to find the
      --  first line break (if any) belonging to the condition.

      procedure If_Statement_Check_1 is
         Line_Breaks : Line_Break_Vector renames All_Line_Breaks;
      begin
         First_If_Line_Break := Last_Index (Line_Breaks) + 1;
      end If_Statement_Check_1;

      procedure If_Statement_Check_2 (Level_Of_If : Nesting_Level) is
         Line_Breaks : Line_Break_Vector renames All_Line_Breaks;
         Min : Nesting_Level := Nesting_Level'Last;
      begin
         --  Find the minimum level:
         for J in First_If_Line_Break .. Last_Index (Line_Breaks) loop
            Min := Nesting_Level'Min (Min, Line_Breaks (J).Level);
         end loop;

         --  Overwrite all line breaks at the minimum level to the level of the
         --  'if':
         for J in First_If_Line_Break .. Last_Index (Line_Breaks) loop
            if Line_Breaks (J).Level = Min then
               Line_Breaks (J).Level := Level_Of_If;
            end if;
         end loop;
      end If_Statement_Check_2;

      function Remove_Extra_Line_Breaks return Char_Vector;
      --  Removes extra NL's. The result has exactly one NL at the beginning, and
      --  exactly one at the end. Also, if Preserve_Blank_Lines is False, we
      --  collapse 3 or more NL's in a row down to 2.  ???It would be cleaner if
      --  we didn't put multiple blank lines in in the first place.
      --
      --  This also converts LF to CRLF if appropriate.

      --  Wide_Text_IO accepts a Form parameter that inserts CR's on windows, but
      --  it doesn't do that on unix, so we insert CR's by hand.

      function Remove_Extra_Line_Breaks return Char_Vector is
         Add_CR : constant Boolean := Out_File_Format = CRLF;
         --  True if we should convert LF to CRLF -- if it was requested on the
         --  command line, or if we're on windows and nothing was requested.
      begin
         --  Optimize the case where we're not changing anything. The reason
         --  Remove_Extra_Line_Breaks keeps the initial NL is that this
         --  optimization wouldn't work otherwise.

         if Preserve_Blank_Lines (Cmd) and then not Add_CR then
            return To_Vector (Out_Buf);
         end if;

         declare
            Result : Char_Vector;
         begin
            while Cur (Out_Buf) = NL loop
               Move_Forward (Out_Buf);
            end loop;
            Append (Result, W_LF);
            --  We don't want a CR here; caller skips the one LF character

            loop
               declare
                  NL_Count : Natural := 0;
               begin
                  while Cur (Out_Buf) = NL loop
                     Move_Forward (Out_Buf);
                     NL_Count := NL_Count + 1;
                  end loop;

                  exit when At_End (Out_Buf);

                  if not Preserve_Blank_Lines (Cmd) and then NL_Count > 2 then
                     NL_Count := 2;
                  end if;

                  for J in 1 .. NL_Count loop
                     if Add_CR then
                        Append (Result, W_CR);
                     end if;
                     Append (Result, W_LF);
                  end loop;
               end;

               pragma Assert (Cur (Out_Buf) /= NL);
               Append (Result, Cur (Out_Buf));
               Move_Forward (Out_Buf);
            end loop;

            if Add_CR then
               Append (Result, W_CR);
            end if;
            Append (Result, W_LF);
            Reset (Out_Buf);
            pragma Assert (Result (1) = NL);
            pragma Assert (Result (2) /= NL);
            if not Add_CR then
               pragma Assert (Result (Last_Index (Result) - 1) /= NL);
               pragma Assert (Result (Last_Index (Result)) = NL);
            end if;
            return Result;
         end;
      end Remove_Extra_Line_Breaks;

      function Munge_Template
        (T    : Ada_Template;
         Kind : Ada_Tree_Kind)
         return Ada_Template;
      --  Modify the template in certain ways based on command-line options and
      --  the like.

      function Munge_Template
        (T    : Ada_Template;
         Kind : Ada_Tree_Kind)
         return Ada_Template
      is
      begin
         if not Arg (Cmd, Rm_Style_Spacing) then
            return T;
         end if;
         declare
            Result : Bounded_W_Str (Max_Length => T'Length * 2);
            X      : Natural := T'First;
            function C return W_Char is (T (X));
            function Match
              (S    : Ada_Template)
               return Boolean is
              (T (X .. Natural'Min (T'Last, X + S'Length - 1)) = S);
         begin
            while X <= T'Last loop
               if Arg (Cmd, Rm_Style_Spacing) then
                  if Match (" (") or else Match (" @(") then
                     X := X + 1; -- skip ' ' before '('
                  elsif Match (" ^:") and then not Match (" ^:=") then
                     X := X + 1; -- skip ' ' before ':'
--                  elsif Kind in
--                      A_Loop_Statement |
--                        A_While_Loop_Statement |
--                        A_For_Loop_Statement |
--                        A_Block_Statement
--                    and then Match (" :")
--                  then
--                     X := X + 1; -- skip ' ' before ':' for statement name
                  end if;
               end if;

               Append (Result, C);
               X := X + 1;
            end loop;

            return Ada_Template (To_String (Result));
         end;
      end Munge_Template;

      function Replacements (T : Ada_Template) return Ada_Template;

      function Replacements (T : Ada_Template) return Ada_Template is
         Temp : W_Str_Access := new W_Str'(W_Str (T));
      begin
         --  Replacements inserting soft line breaks

         Temp := Replace_All (Temp, "? @(~; ~)~", "?[@ (~;@ ~)]~");
         Temp := Replace_All (Temp, "? @(~, ~)~", "?[@ (~,@ ~)]~");
         Temp := Replace_All (Temp, "? := ~~~", "? :=[@ ~~]~");
         Temp := Replace_All (Temp, " renames !", " renames[@ !]");
         --  ???Should be a weaker @, at least for function renamings.
         Temp := Replace_All (Temp, "? and ~ and ~~", "? and[@ ~ and@ ~]~");
         Temp := Replace_All (Temp, " => !", " =>[@ !]");

         --  Replacements inserting tabs

         Temp := Replace_All (Temp, "=>", "^=>");
         Temp :=
           Replace_All
             (Temp,
              "?~, ~~ :? ~~~ !? :=[@ ~~]~",
              "?~, ~~ ^:? ~~~ !? ^2:=[@ ~~]~");
         Temp :=
           Replace_All
             (Temp,
              "?~, ~~ :? ~~~ constant !? :=[@ ~~]~",
              "?~, ~~ ^:? ~~~ constant !? ^2:=[@ ~~]~");
         --  This doesn't cover A_Parameter_Specification, which is handled
         --  specially by Do_Parameter_Specification.

         --  Replacements inserting soft line breaks in comma-separated lists of
         --  defining identifiers.

         Temp := Replace_All (Temp, "?~, ~~ ^:", "?~,@ ~~ ^:");
         --  Note @ without []

         --  Replacements for --no-separate-is

         if not Arg (Cmd, Separate_Is) then
            Temp := Replace_All (Temp, "@ is", " is");
         end if;

         --  If the --no-end-id switch was given, do not insert names after "end"
         --  during the Convert_Tree_To_Ada pass. Instead, insert them during
         --  Insert_Comments_And_Blank_Lines, and only if they are present in the
         --  source.

         if not Arg (Cmd, End_Id) then
            Temp := Replace_All (Temp, "end !1", "end");
            Temp := Replace_All (Temp, "end !2", "end");
            Temp := Replace_All (Temp, "end?1 ~~~", "end");
            Temp := Replace_All (Temp, "end?2 ~~~", "end");
            Temp := Replace_All (Temp, "end?3 ~~~", "end");
         end if;

         return Result : constant Ada_Template := Ada_Template (Temp.all) do
            Free (Temp);
         end return;
      end Replacements;

      procedure Free is new Unchecked_Deallocation
        (Ada_Template, Ada_Template_Ptr);

      procedure Replace_One (Kind : Ada_Tree_Kind; From, To : W_Str);
      --  Replace From with To in the template for Kind

      procedure Replace_One (Kind : Ada_Tree_Kind; From, To : W_Str) is
         Temp : Ada_Template_Ptr := Template_Table (Kind);
      begin
         Template_Table (Kind) :=
           new Ada_Template'(Ada_Template
             (Must_Replace (W_Str (Temp.all), From, To)));
         Free (Temp);
      end Replace_One;

      procedure Init_Template_Table is
      begin
         pragma Assert (not Template_Table_Initialized);
         Template_Table_Initialized := True;

         --  We can't initialize Template_Table with an aggregate, because we
         --  refer to the Kind. The following case-within-loop construction may
         --  look odd, but it accomplishes two goals: the 'case' requires full
         --  coverage, so the items left null are done so explicitly, and the
         --  'for' provides the Kind value to each sub-case that needs it.
         --  The 'case' we're talking about is in Template_For_Kind.

         for Kind in Ada_Tree_Kind loop
            declare
               Temp : Ada_Template_Ptr := Template_For_Kind (Kind);
            begin
               if Temp = null then
                  Template_Table (Kind) := null;
               else
                  Template_Table (Kind) :=
                    new Ada_Template'
                      (Munge_Template (Replacements (Temp.all), Kind));
                  Free (Temp);
               end if;
            end;
         end loop;

         --  Some more-specific replacements

         --  For Separate_Loop_Then, we want a hard line break before
         --  "then" and "loop".

--         if Arg (Cmd, Separate_Loop_Then) then
--            Replace_One (An_If_Path, "@ then$", "$then$");
--            Replace_One (An_Elsif_Path, "@ then$", "$then$");
--            Replace_One (A_While_Loop_Statement, "@ loop$", "$loop$");
--            Replace_One (A_For_Loop_Statement, "@ loop$", "$loop$");
--
--         --  For No_Separate_Loop_Then, we remove the soft line break
--         --  before "then" and "loop".
--
--         elsif Arg (Cmd, No_Separate_Loop_Then) then
--            Replace_One (An_If_Path, "@ then$", " then$");
--            Replace_One (An_Elsif_Path, "@ then$", " then$");
--            Replace_One (A_While_Loop_Statement, "@ loop$", " loop$");
--            Replace_One (A_For_Loop_Statement, "@ loop$", " loop$");
--         end if;
--
--         --  Now do some validity checking on the templates
--
--         for Kind in Ada_Tree_Kind loop
--            declare
--               T : constant Ada_Template_Ptr := Template_Table (Kind);
--
--            begin
--               if T /= null then
--                  declare
--                     subtype Constrained_Query_Count is
--                       Query_Count range 0 .. Num_Queries (Kind);
--                     Subtree_Count : Query_Count := 0;
--
--                  begin
--                     for J in T'Range loop
--                        case T (J) is
--                           when '!' | '?' =>
--                              if J < T'Last and then T (J + 1) in '1' .. '9' then
--                                 pragma Assert
--                                   (Query_Index (Char_To_Digit (T (J + 1))) in
--                                      Constrained_Query_Count);
--
--                              else
--                                 Subtree_Count := Subtree_Count + 1;
--                              end if;
--
--                           --  ??? "{" is always preceded by "$"; we might want a
--                           --  short-hand for "${".
--
--                           when '{' =>
--                              pragma Assert (T (J - 1) = '$');
--
--                           when others =>
--                              null;
--                        end case;
--                     end loop;
--
--                     if Subtree_Count /= Constrained_Query_Count'Last then
--                        raise Program_Error
--                          with "Wrong Subtree_Count: " & Kind'Img;
--                     end if;
--                  end;
--               end if;
--            end;
--         end loop;

         if Debug_Mode then
            Put_Ada_Templates;
         end if;
      end Init_Template_Table;

      procedure Init_Pp_Off_And_On is
         use Scanner;
      begin
         if Arg (Cmd, Pp_Off) /= null then
            pragma Assert (Arg (Cmd, Pp_Off).all /= "");
            Pp_Off_On_Delimiters.Off := new W_Str'
              ("--" & To_Wide_String (Arg (Cmd, Pp_Off).all));
         end if;
         if Arg (Cmd, Pp_On) /= null then
            pragma Assert (Arg (Cmd, Pp_On).all /= "");
            Pp_Off_On_Delimiters.On := new W_Str'
              ("--" & To_Wide_String (Arg (Cmd, Pp_On).all));
         end if;
      end Init_Pp_Off_And_On;

      procedure Subtree_To_Ada
        (Tree            : Ada_Tree;
         Cur_Level       : Nesting_Level;
         Index_In_Parent : Query_Index);
      --  We recursively walk the tree, and for most nodes, take the template
      --  from Template_Table, and pass it to Interpret_Template. Some nodes
      --  need special casing, and bypass the Template_Table. Subtree_To_Ada is
      --  directly recursive, and also mutually recursive with Interpret_Template.

      procedure Convert_Tree_To_Ada (Tree : Ada_Tree);
      --  Subtree_To_Ada with initial values for Cur_Level and Index_In_Parent,
      --  along with some fix-ups. In particular, we add a sentinel Line_Break
      --  at the beginning, and a sentinel Tab at the end.

      type Tree_Stack_Index is new Positive;
      type Tree_Array is array (Tree_Stack_Index range <>) of Ada_Tree;
      package Tree_Stacks is new ASIS_UL.Vectors
        (Tree_Stack_Index,
         Ada_Tree,
         Tree_Array);
      use Tree_Stacks;
      --  use all type Tree_Stacks.Vector;

      Tree_Stack : Tree_Stacks.Vector;
      --  Stack of trees that we're in the process of traversing. Pushed and
      --  popped at the beginning and end of Subtree_To_Ada.

      function Ancestor_Tree
        (N    : Tree_Stack_Index)
        return Ada_Tree;
      --  Returns the N'th ancestor of the current tree. Ancestor (0) is the
      --  current tree, Ancestor (1) is the parent of the current tree, Ancestor
      --  (2) is the grandparent of the current tree, and so on. Nil if the tree
      --  isn't deep enough.

      function Ancestor_Tree
        (N    : Tree_Stack_Index)
        return Ada_Tree is
      begin
         if Last_Index (Tree_Stack) <= N then
            return null;
         else
            return Tree_Stack (Last_Index (Tree_Stack) - N);
         end if;
      end Ancestor_Tree;

      function Parent_Tree return Ada_Tree is (Ancestor_Tree (1));

      Implicit_Null_Statement_Seen : Boolean := False;
      --  See the comments about labels under "when A_Null_Statement =>" below for
      --  an explanation of this.

      function Subp_Decl_With_Hard_Breaks
        (Tree : Ada_Tree;
         Is_Function, Is_Body : Boolean)
         return                 Ada_Template;
      --  For implementing Par_Specs_Threshold. This replaces the soft line break
      --  between parameters with a hard line break. If Is_Function is True, put
      --  a hard line break before "return". If Is_Body is True, put a hard line
      --  break before "is".

      function Subp_Decl_With_Hard_Breaks
        (Tree : Ada_Tree;
         Is_Function, Is_Body : Boolean)
         return                 Ada_Template
      is
         T : Ada_Template renames Template_Table (Tree.Kind).all;
         T1 : constant W_Str :=
           (if Arg (Cmd, Rm_Style_Spacing)
              then Must_Replace (W_Str (T), "[@(~;@ ~)]",  "[$(~;$~)]")
              else Must_Replace (W_Str (T), "[@ (~;@ ~)]", "[$(~;$~)]"));
         T2 : constant W_Str :=
           (if Is_Function
              then Must_Replace (T1, "@1 return", "$ return")
              else T1);
         T3 : constant W_Str :=
           (if Is_Body and then Arg (Cmd, Separate_Is)
             then Must_Replace (T2, "@ is$", "$is$")
             else T2);
      begin
         return Result : constant Ada_Template := Ada_Template (T3) do
            if Assert_Enabled then
--               if Result = T then
--                  Self_Rep.Stdo;
--                  Self_Rep.Put_Ada_Tree (Tree);
--                  Wide_Text_IO.Put_Line ("T = " & W_Str (T));
--                  Wide_Text_IO.Put_Line ("Result = " & W_Str (Result));
--               end if;
               pragma Assert (Result /= T);
            end if;
         end return;
      end Subp_Decl_With_Hard_Breaks;

      package Alternative_Templates is

         --  Some templates that are used instead of the ones in Template_Table

         Prefix_Notation_Call_Alt_Templ_1 : constant Ada_Template :=
           Munge_Template (" @(", A_Function_Call);

         Prefix_Notation_Call_Alt_Templ_2 : constant Ada_Template :=
           Munge_Template ("[$(", A_Function_Call);

         Accept_Statement_Alt_Templ : constant Ada_Template :=
           Munge_Template
             (Labels & "accept !? @(~~)~?[ @(~;@ ~)]~!!",
              An_Accept_Statement);
         --  The last "!!" generates nothing, but satisfies the requirement that
         --  we use all the subtrees.

         --  ???Is the following correct for multi-dim arrays (only some indices
         --  need "range")?
         Constrained_Array_Definition_Alt_Templ_1 : constant Ada_Template :=
           Munge_Template
             ("array @(?range ~, range ~~) of !",
              A_Constrained_Array_Definition);

         Constrained_Array_Definition_Alt_Templ_2 : constant Ada_Template :=
           Munge_Template
             ("array @(?~, ~~) of !",
              A_Constrained_Array_Definition);

         Pragma_Alt_Templ : constant Ada_Template :=
           Munge_Template ("?[ @(~,@ ~)]~", Flat_Pragma_Kinds'First);

         Parameter_Specification_Alt_Templ : constant Ada_Template :=
           Munge_Template (" ^: ", A_Parameter_Specification);

         Block_Statement_Alt_Templ_1 : constant Ada_Template :=
           Munge_Template
             (Labels & "?~~ : ~!" & Handled_Seq_2,
              A_Block_Statement);

         Block_Statement_Alt_Templ_2 : constant Ada_Template :=
           Munge_Template
             (Labels & "?~~ : ~?declare$" & "{~;$~;$$}~" & Handled_Seq_2,
              A_Block_Statement);

         Extended_Return_Statement_Alt_Templ : constant Ada_Template :=
           Munge_Template (Labels & "return !!!", An_Extended_Return_Statement);
         --  The last "!!" generates nothing, but satisfies the requirement that
         --  we use all the subtrees.

      end Alternative_Templates;

      procedure Subtree_To_Ada
        (Tree            : Ada_Tree;
         Cur_Level       : Nesting_Level;
         Index_In_Parent : Query_Index)
      is
         pragma Unreferenced (Index_In_Parent); -- ???Needed?

         Line_Breaks : Line_Break_Vector renames All_Line_Breaks;

         procedure Subtrees_To_Ada
           (Tree               : Ada_Tree;
            Pre, Between, Post : Ada_Template);

         procedure Interpret_Template
           (T         : Ada_Template   := Template_Table (Tree.Kind).all;
            Subtrees  : Ada_Tree_Array := Pp.Actions.Subtrees (Tree);
            Cur_Level : Nesting_Level  := Subtree_To_Ada.Cur_Level;
            Kind      : Ada_Tree_Kind  := Tree.Kind);
         --  Interpret the template, printing literal characters, and recursively
         --  calling Subtree_To_Ada when the template calls for a subnode. Kind is
         --  for debugging.

         procedure Prefix_Notation_Call (Label_Names, Callee, Actuals : Ada_Tree);
         --  This is called for A_Function_Call and A_Procedure_Call_Statement
         --  when the Is_Prefix_Notation subtree is True. Prefix notation calls
         --  have special visibility rules, so we don't want to turn X.F(Y) into
         --  F(X, Y). Label_Names is always empty for function calls.

         procedure Append_Tab
           (Parent, Tree  : Ada_Tree_Base;
            T             : Ada_Template;
            Token_Text    : Symbol;
            Index_In_Line : Tab_Index_In_Line;
            Is_Insertion_Point : Boolean);
         --  Append a Tab_Rec onto Tabs. If Token is Name_Empty, get the token
         --  from the template T.
         --
         --  Handling of "fake tabs":
         --  Fake tabs are used to deal with situations like this:
         --
         --     A_Long_Var_Name      : T          := 123;
         --     X                    : A_Long_Type_Name;
         --     A_Long_Constant_Name : constant T := 123;
         --
         --  where we wish to align the ":" and ":=" tokens. But the
         --  Insert_Alignment algorithm doesn't align things unless subsequent
         --  lines "match", which includes having the same number of tabs. But X
         --  has no ":=", so we add a fake tab so it will match the preceding and
         --  following lines.
         --
         --  Append_Tab inserts a fake tab after each ":" tab. If there is no
         --  ":=" following, the fake tab remains. If there IS a ":=", a real
         --  tab replaces the fake one.
         --
         --  Fake tabs initially have the same position as the preceding ":" tab.
         --  When Insert_Alignment calculates Max_Col, it ignores the fake ones,
         --  so they won't push anything further to the right. It sets the Col of
         --  the fake ones to Max_Col; hence Num_Blanks will be zero, so fake tabs
         --  won't insert any blanks.
         --
         --  Context clauses are handled in a similar manner:
         --
         --     with Ada.Characters.Handling; use Ada.Characters.Handling;
         --     with Ada.Exceptions;
         --     with Ada.Strings;             use Ada.Strings;

         procedure Append_Tab
           (Parent, Tree  : Ada_Tree_Base;
            T             : Ada_Template;
            Token_Text    : Symbol;
            Index_In_Line : Tab_Index_In_Line;
            Is_Insertion_Point : Boolean)
         is
            Text : Symbol;
            Pa              : Ada_Tree_Base := Parent;
            Tr              : Ada_Tree_Base := Tree;

            procedure Maybe_Replace_Fake_Tab;
            --  Replace a fake tab with a real one, if appropriate. In particular,
            --  if the last tab is fake, and the current one has the same
            --  Index_In_Line, Tree, and Parent, then the current one replaces the
            --  fake one.

            function Tab_Token (T : Ada_Template) return Symbol;
            --  Returns the text of the token at the beginning of T, which is the
            --  portion of an Ada_Template immediately following "^".

            procedure Maybe_Replace_Fake_Tab is
            begin
               if Is_Empty (Tabs) then
                  return;
               end if;

               declare
                  Tb : constant Tab_Rec := Last_Element (Tabs);
               begin
                  if Tb.Is_Fake
                    and then Tb.Index_In_Line = Index_In_Line
                    and then Tb.Tree = Tr
                    and then Tb.Parent = Pa
                  then
                     pragma Assert (Tb.Token = Text);
                     pragma Assert
                       ((Text = Name_Assign and then Index_In_Line in 2 | 4)
                        or else
                          (Text = Name_Use and then Index_In_Line = 2));
                     pragma Assert (not Is_Insertion_Point);
                     Delete_Last (Tabs); -- replace fake tab with this real one
                  end if;
               end;
            end Maybe_Replace_Fake_Tab;

            function Tab_Token (T : Ada_Template) return Symbol is
               --  There is a limited number of possibilities, and we take
               --  advantage of that for efficiency. Currently, the only tokens
               --  that can follow "^" in templates are as shown below. This needs
               --  to be changed if we add more tabbing to templates.
               Tok  : Scanner.Token;
               Text : Symbol;
            begin
               if T = "" then
                  pragma Assert
                    (Tree.Kind in
                       A_Parameter_Specification | A_Formal_Object_Declaration);
                  Text := Name_Tab_In_Out;
               else
                  case T (T'First) is
                     when ':' =>
                        if Has_Prefix (W_Str (T), Prefix => ":=") then
                           Text := Name_Assign;
                        else
                           Text := Name_Colon;
                        end if;
                     when '|' =>
                        Text := Name_Bar;
                     when '=' =>
                        pragma Assert (Has_Prefix (W_Str (T), Prefix => "=>"));
                        Text := Name_Arrow;
                     when 'a' =>
                        pragma Assert (Has_Prefix (W_Str (T), Prefix => "at"));
                        Text := Name_At;
                     when 'r' =>
                        pragma Assert (Has_Prefix (W_Str (T), Prefix => "range"));
                        Text := Name_Range;
                     when '.' =>
                        pragma Assert (Tree.Kind in A_Component_Clause);
                        pragma Assert (Has_Prefix (W_Str (T), Prefix => ".."));
                        Text := Name_Dot_Dot;
                     when ']' =>
                        pragma Assert (Tree.Kind in A_Component_Clause);
                        Text := Name_R_Sq;
                        goto Skip_Assertion; -- ']' is not a legal token
                     when others =>
                        pragma Assert (False);
                  end case;
                  if Assert_Enabled then
                     Tok := Scanner.Get_Token (W_Str (T), LAL_UL.Ada_Version);
                     pragma Assert (Text = Tok.Normalized);
                     pragma Assert (Tok.Sloc.First = 1);
                  end if;
                  <<Skip_Assertion>>
               end if;
               pragma Assert
                 (Text in
                    Name_Tab_In_Out |
                    Name_Assign |
                    Name_Colon |
                    Name_Arrow |
                    Name_Bar |
                    Name_At |
                    Name_Range |
                    Name_Dot_Dot |
                    Name_R_Sq);
               return Text;
            end Tab_Token;

         --  Start of processing for Append_Tab

         begin
            if not Alignment_Enabled (Cmd) then
               return;
            end if;

            if Tree /= null and then Tree.Kind = A_With_Clause then
--               if Is_Nil (Get (Tree, Has_Limited))
--                 and then Is_Nil (Get (Tree, Has_Private))
--               then
                  Pa   := null;
                  Tr   := null;
                  Text := Name_With;
--               else
--                  return; -- ignore "limited with" and "private with"
--               end if;
            elsif Token_Text = Name_Empty then
               if Is_Insertion_Point then
                  Text := Name_Tab_Insertion_Point;
               else
                  Text := Tab_Token (T);
               end if;
            else
               Text := Token_Text;
            end if;

            Maybe_Replace_Fake_Tab;

            pragma Assert
              (Point (Out_Buf) =
               Last_Position (Out_Buf) + 1); -- ???Do we need Last_Position?
            Append
              (Tabs,
               Tab_Rec'
                 (Pa,
                  Tr,
                  Token           => Text,
                  Mark            => Mark (Out_Buf, '^'),
                  Index_In_Line   => Index_In_Line,
                  Col             => <>,
                  Num_Blanks      => <>,
                  Is_Fake         => False,
                  Is_Insertion_Point => Is_Insertion_Point));
            pragma Assert
              (Position (Out_Buf, Last_Element (Tabs).Mark) =
               Last_Position (Out_Buf) + 1);

            --  Append a fake tab if appropriate

--            if Tree /= null and then not Is_Insertion_Point then
--               case Tree.Kind is
--                  when A_Variable_Declaration |
--                    A_Constant_Declaration |
--                    An_Integer_Number_Declaration |
--                    A_Real_Number_Declaration |
--                    A_Discriminant_Specification |
--                    A_Component_Declaration |
--                    A_Return_Variable_Specification =>
--                     if Index_In_Line = 1 then
--                        pragma Assert (Text = Name_Colon);
--                        Append
--                          (Tabs,
--                           Tab_Rec'
--                             (Parent          => Pa,
--                              Tree            => Tr,
--                              Token           => Name_Assign,
--                              Mark            => Mark (Out_Buf, '^'),
--                              Index_In_Line   => 2,
--                              Col             => <>,
--                              Num_Blanks      => <>,
--                              Is_Fake         => True,
--                              Is_Insertion_Point => False));
--                     end if;
--
--                  when A_Parameter_Specification | A_Formal_Object_Declaration =>
--                     if Index_In_Line = 3 then
--                        pragma Assert (Text = Name_Tab_In_Out);
--                        Append
--                          (Tabs,
--                           Tab_Rec'
--                             (Parent          => Pa,
--                              Tree            => Tr,
--                              Token           => Name_Assign,
--                              Mark            => Mark (Out_Buf, '^'),
--                              Index_In_Line   => 4,
--                              Col             => <>,
--                              Num_Blanks      => <>,
--                              Is_Fake         => True,
--                              Is_Insertion_Point => False));
--                     end if;
--
--                  when A_With_Clause =>
--                     if Index_In_Line = 1 then
--                        pragma Assert (Text = Name_With);
--                        Append
--                          (Tabs,
--                           Tab_Rec'
--                             (Parent          => Pa,
--                              Tree            => Tr,
--                              Token           => Name_Use,
--                              Mark            => Mark (Out_Buf, '^'),
--                              Index_In_Line   => 2,
--                              Col             => <>,
--                              Num_Blanks      => <>,
--                              Is_Fake         => True,
--                              Is_Insertion_Point => False));
--                     end if;
--
--                  when A_Variant |
--                    An_Aspect_Specification |
--                    A_For_All_Quantified_Expression |
--                    A_For_Some_Quantified_Expression |
--                    An_Assignment_Statement |
--                    A_Case_Path |
--                    A_Select_Path |
--                    An_Or_Path |
--                    A_Case_Expression_Path |
--                    A_Component_Clause |
--                    An_Exception_Handler |
--                    An_Exception_Renaming_Declaration |
--                    An_Exception_Declaration =>
--                     null;
--
--                  when A_Pragma_Argument_Association |
--                    A_Discriminant_Association       |
--                    A_Record_Component_Association   |
--                    An_Array_Component_Association   |
--                    A_Parameter_Association          |
--                    A_Generic_Association            =>
--                     null;
--
--                  when others =>
--                     --  No other tree kinds have tabs
--                     pragma Assert (False);
--               end case;
--            end if;
         end Append_Tab;

         procedure Subtrees_To_Ada
           (Tree               : Ada_Tree;
            Pre, Between, Post : Ada_Template)
         is
            procedure Check_Between;
            --  Assert that Between doesn't contain any indentation or similar, so
            --  we don't need special processing as for Keep_Indentation.

            function Keep_Indentation (Post : Ada_Template) return Ada_Template;
            --  Remove everything from Post except for indentation commands

            procedure Check_Between is
            begin
               for X of Between loop
                  if X in '{' | '}' | '[' | ']' | '(' | ')' | '&' |
                    '!' | '?' | '~'
                  then
--                     Self_Rep.Stdo;
--                     Self_Rep.Put_Ada_Tree (Tree);
--                     Wide_Text_IO.Put_Line
--                       ("Incorrect Between string: " & W_Str (Between));
                     pragma Assert (False);
                  end if;
               end loop;
            end Check_Between;

            pragma Debug (Check_Between);

            function Keep_Indentation (Post : Ada_Template) return Ada_Template is
               Result : Bounded_W_Str (Max_Length => Post'Length);
            begin
               for X of Post loop
                  pragma Assert (X not in '(' | ')');
                  if X in '{' | '}' | '[' | ']' then
                     Append (Result, X);
                  end if;
               end loop;
               return Ada_Template (To_String (Result));
            end Keep_Indentation;

--            pragma Assert (Tree.Kind in Flat_List_Kinds);
            Prev_With : Ada_Tree_Base := null;
            --  See Use_Same_Line below

         begin
            if Subtree_Count (Tree) = 0 then
               return;
            end if;

            Interpret_Template (Pre, Subtrees => Empty_Tree_Array);

            for Index in 1 .. Subtree_Count (Tree) loop
               declare
                  Subt : constant Ada_Tree := Subtree (Tree, Index);

                  function Use_Same_Line return Boolean;
                  --  Special case for use_package_clauses: We want to print "with
                  --  A.B; use A.B;" on one line. Also, things like "with A.B; use
                  --  A; use A.B;". This returns True in these cases. We don't do
                  --  this special processing for use type clauses.

                  function Has_Prefix (X, Y : Ada_Tree) return Boolean; -- with
--                     Pre => X.Kind in Usage_Names | A_Selected_Component
--                     and then Y.Kind in Usage_Names | A_Selected_Component;
                     --  True if X contains Y, as in "A.B.C.D" contains "A.B".
                     --  I.e. if Y is a prefix of X.

                  function Has_Prefix (X, Y : Ada_Tree) return Boolean is
                  begin
                     return raise Program_Error;
--                     if Ref (X) = Ref (Y) then
--                        return True;
--                     elsif X.Kind in Usage_Names then
--                        return False;
--                     else
--                        pragma Assert (X.Kind = A_Selected_Component);
--                        return Has_Prefix (Subtree (X, 1), Y);
--                     end if;
                  end Has_Prefix;

                  function Use_Same_Line return Boolean is
                  begin
                     --  For a with clause followed by one or more use package
                     --  clauses, Prev_With will be the with clause when
                     --  processing the use clauses. Otherwise, Prev_With is null.

                     if Prev_With = null
                       or else Arg (Cmd, Use_On_New_Line)
                     then
                        return False; -- usual case
                     end if;

                     declare
                        pragma Assert (Prev_With.Kind = A_With_Clause);
                        With_Names : constant Ada_Tree := Subtree (Prev_With, 3);
                        Next_Subtree : constant Ada_Tree :=
                          Subtree (Tree, Index + 1);
                     begin
                        if Next_Subtree.Kind = A_Use_Package_Clause
                          and then Subtree_Count (Subtree (Next_Subtree, 1)) = 1
                          and then Subtree_Count (With_Names) = 1
                        then
                           declare
                              W : constant Ada_Tree := Subtree (With_Names, 1);
                              U : constant Ada_Tree :=
                                Subtrees (Subtree (Next_Subtree, 1)) (1);
                           begin
                              if Has_Prefix (W, U) or else Has_Prefix (U, W) then
                                 return True;
                              end if;
                           end;
                        end if;
                     end;

                     return False; -- usual case
                  end Use_Same_Line;

               begin
                  pragma Assert (Tree.Kind not in An_If_Path | An_Elsif_Path);
                  --  No need for If_Statement_Check here
                  Subtree_To_Ada
                    (Subt,
                     New_Level (Tree, Index, Cur_Level, Pre & Between & Post),
                     Index);
                  --  ???Shouldn't this use the entire template?

if Subt /= null then
                  case Subt.Kind is
                     when A_With_Clause =>
--                        if Is_Nil (Get (Subt, Has_Limited))
--                          and then Is_Nil (Get (Subt, Has_Private))
--                        then
                           Prev_With := Subt;
--                        else
--                           --  ignore "limited with" and "private with"
--                           Prev_With := null;
--                        end if;
                     when A_Use_Package_Clause =>
                        null; -- Leave Prev_With alone
                     when others =>
                        Prev_With := null;
                  end case;

                  if Index < Subtree_Count (Tree) then
                     declare
                        Same_Line : constant Boolean := Use_Same_Line;
                        pragma Assert (if Same_Line then Between = ";$");
                        Tween : constant Ada_Template :=
                          (if
                             Same_Line
                           then
                             (if Prev_With = Subtree (Tree, Index) then ";@ "
                              else ";$")
                           else -- else ";@1 "???
                           Between);
                     begin
                        if Subt.Kind /= A_Comment then
                           Interpret_Template
                             (Tween, Subtrees => Empty_Tree_Array);
                        end if;
                        if Same_Line then
                           Append_Tab
                             (Parent        => null,
                              Tree          => null,
                              T             => "",
                              Token_Text    => Name_Use,
                              Index_In_Line => 2,
                              Is_Insertion_Point => False);
                        end if;
                     end;

                  else
                     pragma Assert (Index = Subtree_Count (Tree));
                     if Subt.Kind = A_Comment then
                        Interpret_Template
                          (Keep_Indentation (Post), Subtrees => Empty_Tree_Array);
                     else
                        Interpret_Template (Post, Subtrees => Empty_Tree_Array);
                     end if;
                  end if;
end if;
               end;
            end loop;
         end Subtrees_To_Ada;

         procedure Interpret_Template
           (T         : Ada_Template   := Template_Table (Tree.Kind).all;
            Subtrees  : Ada_Tree_Array := Pp.Actions.Subtrees (Tree);
            Cur_Level : Nesting_Level  := Subtree_To_Ada.Cur_Level;
            Kind      : Ada_Tree_Kind  := Tree.Kind)
         is

            pragma Assert (T = Munge_Template (T, Kind));
            J : Positive := T'First;
            subtype Subtrees_Index is Query_Index range 1 .. Subtrees'Last;
            Used : array (Subtrees_Index) of Boolean := (others => False);
            Cur_Subtree_Index : Query_Count                       := 0;
            Numeric_Arg       : Boolean;
            C                 : W_Char;

            function Debug_Template return Symbol;

            function Debug_Template return Symbol is
            begin
               if False then
                  return W_Intern
                      ("X" & W_Str (T) & "X    [" & From_UTF8 (Image (J)) & "]");
               else
                  return Name_Empty;
               end if;
            end Debug_Template;

            Nesting_Increment : Nesting_Level;

         --  Start of processing for Interpret_Template

         begin
            while J <= T'Last loop
               Numeric_Arg := False;
               C           := T (J);

               case C is
                  --  The following characters are not currently used in templates
                  --  (as literal text, or as the initial character of a special
                  --  character sequence); reserved for future use.

                  when '0' .. '9' |
                    '~'           |
                    '#'           |
                    '*'           |
--                    '_'           |
                    '"'           |
                    '\'           =>
                     raise Program_Error with "Illegal template character";

                  when '$' | '%' =>
                     Append_Line_Break
                       (Hard     => True,
                        Affects_Comments => C = '$',
                        Level    => Cur_Level,
                        Kind     => Kind,
                        Template => Debug_Template);
                  when '@' =>
                     if J < T'Last and then T (J + 1) in '0' .. '9' then
                        J                 := J + 1;
                        Nesting_Increment :=
                          Nesting_Level (Char_To_Digit (T (J)));
                     else
                        Nesting_Increment := 0;
                     end if;
                     Append_Line_Break
                       (Hard     => False,
                        Affects_Comments => False,
                        Level    => Cur_Level + Nesting_Increment,
                        Kind     => Kind,
                        Template => Debug_Template);

                  when '{' =>
                     Indent (PP_Indentation (Cmd));
                  when '}' =>
                     Indent (-PP_Indentation (Cmd));

                  when '[' =>
                     Indent (PP_Indent_Continuation (Cmd));
                  when ']' =>
                     Indent (-PP_Indent_Continuation (Cmd));

                  when '(' =>
                     Buffered_Output.Put_Char (C);
                     Indent (1); -- extra indentation
                  when ')' =>
                     Buffered_Output.Put_Char (C);
                     Indent (-1);

                  when '^' | '&' =>
                     declare
                        Index_In_Line : Tab_Index_In_Line;
                        Par           : Ada_Tree := Parent_Tree;
                     begin
                        if J < T'Last and then T (J + 1) in '0' .. '9' then
                           J             := J + 1;
                           Index_In_Line :=
                             Tab_Index_In_Line (Char_To_Digit (T (J)));

                        else
                           Index_In_Line := 1;
                        end if;
                        if Par = Tree then
                           Par := Ancestor_Tree (2); -- up one more level
                        end if;
                        Append_Tab
                          (Par,
                           Tree,
                           T (J + 1 .. T'Last),
                           Name_Empty,
                           Index_In_Line => Index_In_Line,
                           Is_Insertion_Point => C = '&');
                     end;

                  when '/' =>
                     Cur_Subtree_Index := Cur_Subtree_Index + 1;
                     Used (Cur_Subtree_Index) := True;

                  when '!' | '?' =>
                     if J < T'Last and then T (J + 1) in '0' .. '9' then
                        Numeric_Arg := True;
                        J           := J + 1;

                     else
                        Cur_Subtree_Index := Cur_Subtree_Index + 1;
                     end if;

                     declare
                        Subtree_Index : Query_Index;

                     begin
                        if Numeric_Arg then
                           Subtree_Index := Query_Index (Char_To_Digit (T (J)));

                        else
                           Subtree_Index := Cur_Subtree_Index;
                        end if;
                        pragma Assert (Subtree_Index in Subtrees_Index);
                        --  Put ("Subtree_Index = \1, not in \2..\3 <<\4>>\n",
                        --  Image (Subtree_Index), Image (Subtrees'First), Image
                        --  (Subtrees'Last), "???Image (Tr.Kind)");

                        declare
                           Subt : constant Ada_Tree :=
                             Subtrees (Subtree_Index);

                        begin
                           Used (Subtree_Index) := True;
                           if C = '!' then
                              if Tree.Kind in An_If_Path | An_Elsif_Path then
                                 pragma Assert (Subtree_Index = 1);
                                 If_Statement_Check_1;
                              end if;

                              Subtree_To_Ada
                                (Subt,
                                 New_Level (Tree, Subtree_Index, Cur_Level, T),
                                 Subtree_Index);

                              if Tree.Kind in An_If_Path | An_Elsif_Path then
                                 If_Statement_Check_2 (Cur_Level);
                              end if;

                           else
                              pragma Assert (C = '?');

                              declare
                                 function Scan_To_Tilde return Positive;

                                 function Scan_To_Tilde return Positive is
                                 begin
                                    loop
                                       J := J + 1;
                                       exit when T (J) = '~';
                                    end loop;
                                    return J - 1;
                                 end Scan_To_Tilde;

                                 Pre_First : constant Positive := J + 1;
                                 Pre_Last  : constant Positive := Scan_To_Tilde;
                                 pragma Assert (T (J) = '~');

                                 Between_First : constant Positive := J + 1;
                                 Between_Last  : constant Positive :=
                                   Scan_To_Tilde;
                                 pragma Assert (T (J) = '~');

                                 Post_First : constant Positive := J + 1;
                                 Post_Last  : constant Positive := Scan_To_Tilde;
                                 pragma Assert (T (J) = '~');

                              begin
                                 Used (Subtree_Index) := True;
                                 --  ???The following could use some cleanup
                                 if Subt /= null then
                                    case Subt.Kind is
                                       when Ada_List =>
                                          Append (Tree_Stack, Subt); -- push
                                          Subtrees_To_Ada
                                            (Subt,
                                             T (Pre_First .. Pre_Last),
                                             T (Between_First .. Between_Last),
                                             T (Post_First .. Post_Last));
                                          Delete_Last (Tree_Stack); -- pop

                                       when others =>
                                          Interpret_Template
                                            (T (Pre_First .. Pre_Last),
                                             Subtrees => Empty_Tree_Array);
                                          --  ???
                                          --  if False and then Between /= "" then
                                          --  Put ("\1, \2: ???Between = <<\3>>, " &
                                          --  "T = <<\4>>\n", "???Image (Tr.Kind)",
                                          --  Image (Subt.Kind), String (Between),
                                          --  String (T)); pragma Assert (Between =
                                          --  ""); end if;
                                          pragma Assert
                                            (Kind not in An_If_Path | An_Elsif_Path);
                                          --  No need for If_Statement_Check here
                                          Subtree_To_Ada
                                            (Subt,
                                             New_Level
                                               (Tree,
                                                Subtree_Index,
                                                Cur_Level,
                                                T),
                                             Subtree_Index);
                                          Interpret_Template
                                            (T (Post_First .. Post_Last),
                                             Subtrees => Empty_Tree_Array);
                                    end case;
                                 end if;
                              end;
                           end if;
                        end;
                     end;

                  when ';' =>
                     if Implicit_Null_Statement_Seen then
                        Implicit_Null_Statement_Seen := False;

                     else
                        Buffered_Output.Put_Char (C);
                     end if;

                  when others =>
                     Buffered_Output.Put_Char (C);

               end case;

               J := J + 1;
            end loop;

            if Used /= (Subtrees_Index => True) then -- ???
               Buffered_Output.Put ("???Not all used: \1", "???Image (Tr.Kind)");
            end if;
            --  ???pragma Assert (Used = (Subtrees_Index => True));
         end Interpret_Template;

         use Alternative_Templates;

         function Past_Call_Threshold (Actuals : Ada_Tree) return Boolean is
           (raise Program_Error);
--            (Natural (Subtree_Count (Actuals)) >
--               Arg (Cmd, Call_Threshold)
--               and then
--               (for some Assoc of Subtrees (Actuals) =>
--                  Subtree (Assoc, 1).Kind /= Not_An_Element));
         --  True if there are more parameter associations than the threshold,
         --  and at least one of them is named.

         function Hard_Breaks_For_Call (Kind : Ada_Tree_Kind) return Ada_Template
           is (Ada_Template (Must_Replace
                (W_Str (Template_Table (Kind).all),
                 "@ (~,@ ~)", "%(~,%~)")));
         --  We use % instead of $ here, so that the indentation of these will not
         --  affect following comments.

         procedure Prefix_Notation_Call
           (Label_Names, Callee, Actuals : Ada_Tree)
         is
--
--            --  For X.F(Y,Z), which is shorthand for F(X,Y,Z), First is X and Rest
--            --  is Y,Z.
--
--            First : constant Ada_Tree := Subtree (Actuals, 1);
--
--            The_Rest : aliased Ada_Tree_Rec :=
--                (Kind          => An_Association_List,
--                 Checks        => Asis.Extensions.Empty_Check_Set,
--                 Subtree_Count => Subtree_Count (Actuals) - 1,
--                 Sloc          => Asis.Text.Nil_Span,
--                 Subtrees      => Subtrees (Actuals)
--                   (2 .. Subtree_Count (Actuals)));
--            Rest : constant Ada_Tree := The_Rest'Unchecked_Access;
--            Past : constant Boolean := Past_Call_Threshold (Rest);
--
         begin
            raise Program_Error;
--            if Subtree_Count (Label_Names) /= 0 then
--               raise Program_Error
--                 with "labeled prefix calls not yet implemented";
--            end if;
--
--            --  ???Work around possible bug in Function_Call_Parameters. Not sure
--            --  why Callee would be A_Selected_Component.
--
--            if Callee.Kind /= A_Selected_Component then
--               Subtree_To_Ada (First, Cur_Level + 1, Index_In_Parent => 1);
--               Buffered_Output.Put (".");
--            end if;
--            Subtree_To_Ada (Callee, Cur_Level + 1, Index_In_Parent => 2);
--            Subtrees_To_Ada
--              (Rest,
--               Pre     =>
--                 (if Past
--                    then Prefix_Notation_Call_Alt_Templ_2
--                    else Prefix_Notation_Call_Alt_Templ_1),
--               Between => (if Past then ",$" else ", "),
--               Post    => (if Past then ")]" else ")"));
         end Prefix_Notation_Call;

         procedure Maybe_Blank_Line;

         procedure Maybe_Blank_Line is
            Insert_Blank_Line_Before : Boolean := False;
         begin
            if not Insert_Blank_Lines (Cmd) then
               return;
            end if;

            if Tree.Kind = A_Compilation_Unit then
               Insert_Blank_Line_Before := True;
            end if;

            if Tree.Kind in
                An_Ordinary_Type_Declaration |
               --  ???(if rec etc)A_Record_Type_Definition
               --  A_Derived_Record_Extension_Definition

                  A_Task_Type_Declaration |
                  A_Protected_Type_Declaration |
                  A_Single_Task_Declaration |
                  A_Single_Protected_Declaration |
                  A_Procedure_Body_Declaration |
                  A_Function_Body_Declaration |
                  A_Package_Declaration | -- ???(non lib unit)
                  A_Package_Body_Declaration |
                  A_Task_Body_Declaration |
                  A_Protected_Body_Declaration |
                  An_Entry_Body_Declaration |
                  A_Generic_Procedure_Declaration |
                  A_Generic_Function_Declaration |
                  A_Generic_Package_Declaration |
                  An_Enumeration_Type_Definition | --???(if big)
                  A_Loop_Statement |
                  A_While_Loop_Statement |
                  A_For_Loop_Statement |
                  A_Block_Statement |
                  An_Extended_Return_Statement |
                  An_Accept_Statement |
                  A_Selective_Accept_Statement |
                  A_Timed_Entry_Call_Statement |
                  A_Conditional_Entry_Call_Statement |
                  An_Asynchronous_Select_Statement |
                  An_If_Path | --???look up to If_Statement, then up to list.
                  An_Elsif_Path |
                  An_Else_Path |
                  A_Case_Path |
                  A_Record_Representation_Clause
   --           An_Exception_Handler |???

            then
               declare
                  Parent : constant Ada_Tree := Parent_Tree;
               begin
                  null;
--                  if Parent.Kind in Flat_List_Kinds then
--                     if Subtree (Parent, 1) /= Tree then
--                        Insert_Blank_Line_Before := True;
--                     end if;
--                  end if;
               end;
            end if;

            if Insert_Blank_Line_Before then
               pragma Assert (Line_Breaks (Last (Line_Breaks)).Hard);
               pragma Assert
                 (Point (Out_Buf) =
                  Last_Position (Out_Buf) + 1); -- ???Do we need Last_Position?
               pragma Assert
                 (Position (Out_Buf, Line_Breaks (Last (Line_Breaks)).Mark) =
                  Last_Position (Out_Buf));
               pragma Assert (Lookback (Out_Buf) = NL);
               --  There should already be a hard line break here; we're about to
               --  add another one.

               Append_Line_Break
                 (Hard     => True,
                  Affects_Comments => False,
                  Level    => 0,
                  Kind     => Tree.Kind,
                  Template => Intern ("Maybe_Blank_Line"));
            end if;
         end Maybe_Blank_Line;

         Index : Query_Index := 1;

         --  Procedures for formatting the various kinds of node that are not
         --  fully covered by Template_Table:

--         procedure Do_Accept_Statement;
--         procedure Do_Array_Aggregate;
--         procedure Do_Association;
--         procedure Do_Attribute_Reference;
--         procedure Do_Block_Statement;
         procedure Do_Compilation_Unit;
--         procedure Do_Comment;
--         procedure Do_Case_Path;
--         procedure Do_Case_Statement;
--         procedure Do_Component_Clause;
--         procedure Do_Constrained_Array_Definition; -- also generic formal
--         procedure Do_Def_Name;
--         procedure Do_Extended_Return_Statement;
--         procedure Do_Extension_Aggregate;
--         procedure Do_Function_Call;
--         procedure Do_List;
--         procedure Do_Literal;
--         procedure Do_Null_Statement;
--         procedure Do_Ordinary_Type_Declaration;
--         procedure Do_Parameter_Specification; -- also Formal_Object_Declaration
--         procedure Do_Pragma;
--         procedure Do_Procedure_Call_Statement; -- also Entry_Call_Statement
--         procedure Do_Qualified_Expression;
--         procedure Do_Record_Aggregate;
--         procedure Do_Single_Task_Declaration;
--         procedure Do_Subp_Decl -- subprograms and the like
--           (Is_Function, Is_Body : Boolean;
--            Params_Query         : Structural_Queries);
--         procedure Do_Subtype_Indication;
--         procedure Do_Task_Type_Declaration;
--         procedure Do_Usage_Name;
--
         procedure Do_Others; -- anything not listed above

--         procedure Do_Accept_Statement is
--         begin
--            --  If there are no statements or exception handlers, use short form
--
--            if Subtree_Count (Subtree (Tree, 5)) = 0
--              and then Subtree_Count (Subtree (Tree, 6)) = 0
--            then
--               Interpret_Template (Accept_Statement_Alt_Templ);
--            else
--               Interpret_Template;
--            end if;
--         end Do_Accept_Statement;
--
--         procedure Do_Array_Aggregate is
--         begin
--            if Parent_Tree.Kind = An_Enumeration_Representation_Clause then
--               Interpret_Template ("?[@(~,@ ~)]~");
--            else
--               Interpret_Template;
--            end if;
--         end Do_Array_Aggregate;
--
--         procedure Do_Association is
--            --  Some have a single name before the "=>", and some have a list
--            --  separated by "|". Single_Name_Only is True in the former case.
--            --  Positional_Notation is True if there are no names (no "=>").
--            --  Single_Name is True if there is a single name before "=>",
--            --  regardless of whether a list is allowed.
--            Single_Name_Only : constant Boolean :=
--              (case Tree.Kind is
--                 when A_Pragma_Argument_Association |
--                   A_Parameter_Association |
--                   A_Generic_Association =>
--                   True,
--                 when A_Discriminant_Association |
--                   A_Record_Component_Association |
--                   An_Array_Component_Association =>
--                   False,
--                 when others => False); -- Can't happen
--            Positional_Notation : constant Boolean :=
--              (if Single_Name_Only then Subtree (Tree, 1).Kind = Not_An_Element
--               else Subtree_Count (Subtree (Tree, 1)) = 0 -- list length 0?
--               );
--         begin
--            if Positional_Notation then
--               Interpret_Template ("?~~~!");
--            --  The "?~~~" generates nothing.
--
--            else
--               declare
--                  Single_Name : constant Boolean :=
--                    Single_Name_Only or else Subtree_Count (Subtree (Tree, 1)) = 1;
--               begin
--                  --  This is needed because the "[]" is not properly nested with
--                  --  the "?~~~".
--                  if Single_Name then
--                     Interpret_Template ("?~~ ^=>[@ ~!]");
--                  else
--                     Interpret_Template ("?~ ^|@ ~ ^=>[@ ~!]");
--                  end if;
--               end;
--            end if;
--         end Do_Association;
--
--         procedure Do_Attribute_Reference is
--            Attribute_Designator_Id : constant String :=
--              To_Lower (Str (Subtree (Tree, 2).Ref_Name).S);
--         begin
--            --  If the Attribute_Designator_Identifier is "Update", then we need
--            --  to avoid generating an extra pair of parentheses, because ASIS
--            --  represents X'Update(X => Y) as an attribute reference whose
--            --  Attribute_Designator_Expressions is a list containing the
--            --  aggregate (X => Y), so it would otherwise come out as
--            --      X'Update((X => Y)).
--
--            if Attribute_Designator_Id = "update" then
--               pragma Assert (Tree.Kind = An_Implementation_Defined_Attribute);
--               Interpret_Template ("!'[@!? @~, ~~]");
--            else
--               Interpret_Template;
--            end if;
--         end Do_Attribute_Reference;
--
--         procedure Do_Block_Statement is
--         begin
--            --  If Block_Declarative_Items is empty, leave off the "declare"
--
--            if Subtree_Count (Subtree (Tree, 3)) = 0 then
--               Interpret_Template (Block_Statement_Alt_Templ_1);
--            else
--               Interpret_Template (Block_Statement_Alt_Templ_2);
--            end if;
--         end Do_Block_Statement;

         use Buffered_Output;

         procedure Do_Compilation_Unit is
         begin
   --          Put ("--  \1 = \2", "Unit_Kind", Capitalize (Tree.Unit_Kind'Img));
   --          Interpret_Template ("$", Subtrees => Empty_Tree_Array);
   --          Put
   --            ("--  \1 = \2",
   --             "Unit_Class",
   --             Capitalize (Tree.Unit_Class'Img));
   --          Interpret_Template ("$", Subtrees => Empty_Tree_Array);
   --          Put
   --            ("--  \1 = \2",
   --             "Unit_Origin",
   --             Capitalize (Tree.Unit_Origin'Img));
   --          Interpret_Template ("$", Subtrees => Empty_Tree_Array);
   --          Interpret_Template ("$", Subtrees => Empty_Tree_Array);
            Subtrees_To_Ada
              (Subtree (Tree, 1),
               Pre     => "",
               Between => ";$",
               Post    => ";$$");
            --  If it's a subunit, we need "separate (Parent.Name)"

--            if Tree.Unit_Kind in A_Subunit then
--               declare
--                  N    : constant W_Str :=
--                    To_W_Str (Tree.Unit_Full_Name);
--                  Last : Positive       := N'Last;
--
--               begin
--                  --  Determine parent name by searching for the last '.'
--
--                  while N (Last) /= '.' loop
--                     Last := Last - 1;
--                  end loop;
--                  Last := Last - 1;
--
--                  Put
--                    ("separate\1(\2)",
--                     (if Arg (Cmd, Rm_Style_Spacing) then "" else " "),
--                     N (1 .. Last));
--                  Interpret_Template ("$", Subtrees => Empty_Tree_Array);
--               end;
--            end if;
--
--            case Tree.Unit_Class is
--               when A_Private_Declaration =>
--                  Put ("private ");
--
--               when A_Public_Declaration       |
--                 A_Public_Body                 |
--                 A_Public_Declaration_And_Body |
--                 A_Private_Body                |
--                 A_Separate_Body               =>
--                  null;
--
--               when Not_A_Class =>
--                  raise Program_Error;
--            end case;

            Subtree_To_Ada
              (Subtree (Tree, 2),
               Cur_Level + 1,
               Index_In_Parent => 2);
            Put (";");
            Interpret_Template ("$", Subtrees => Empty_Tree_Array);
            Subtrees_To_Ada
              (Subtree (Tree, 3),
               Pre     => "",
               Between => ";$",
               Post    => ";$");
         end Do_Compilation_Unit;

--         procedure Do_Comment is
--            pragma Assert (Tree.Text in Scanner.Gen_Plus | Scanner.Gen_Minus);
--            S : constant W_Str := To_W_Str (Tree.Text);
--            --  These are the only ones used, for now.
--            Gen_Indent : constant Natural :=
--              Good_Column
--                (PP_Indentation (Cmd),
--                 Arg (Cmd, Max_Line_Length) - Cur_Indentation - S'Length);
--            pragma Assert ((Gen_Indent mod PP_Indentation (Cmd)) = 0);
--         begin
--            pragma Assert (Check_Whitespace);
--            Check_Whitespace := False;
--            Interpret_Template
--              ((1 .. Gen_Indent => ' '),
--               Subtrees => Empty_Tree_Array);
--            Interpret_Template
--              (Ada_Template (S),
--               Subtrees => Empty_Tree_Array);
--            Check_Whitespace := True;
--            Interpret_Template ("$", Subtrees => Empty_Tree_Array);
--            if Tree.Text = Scanner.Gen_Minus then
--               Interpret_Template ("$", Subtrees => Empty_Tree_Array);
--            end if;
--         end Do_Comment;
--
--         procedure Do_Case_Path is
--            Stms : constant Ada_Tree := Subtree (Tree, 2);
--
--         begin
--            --  If the statement list is a single block statement that starts on
--            --  the same line as the "when", then we assume the user wants to keep
--            --  it that way. For example:
--            --
--            --     when Upper_Case => Upper_Case_Case : begin
--
--            if Subtree_Count (Stms) = 1
--              and then Subtree (Stms, 1).Kind = A_Block_Statement
--              and then Subtree (Stms, 1).Sloc.First_Line = Tree.Sloc.First_Line
--            then
--               Interpret_Template ("when ?[@~ |@ ~]~ => " & "?~~;$~");
--
--            else
--               Interpret_Template;
--            end if;
--         end Do_Case_Path;
--
--         procedure Do_Case_Statement is
--            --  If all the "when"s appear in the same column as "case", then we
--            --  assume that's what the user intended, and avoid indenting the
--            --  "when"s. ???But the old gnatpp doesn't do that, so disable it
--            --  for now.
--
--            Case_Col : constant Positive := Tree.Sloc.First_Column;
--            --  Column in which "case" appears
--            Whens_Col : Positive :=
--              Subtree (Subtree (Tree, 3), 1).Sloc.First_Column;
--         --  Column in which all the "when"s appear, if they're all the same
--
--         begin
--            for W of Subtrees (Subtree (Tree, 3)) loop
--               if W.Sloc.First_Column /= Whens_Col then
--                  Whens_Col := Positive'Last; -- not all the same
--               end if;
--            end loop;
--
--            Whens_Col := Positive'Last; -- ???disable for now
--            if Case_Col = Whens_Col and then Case_Col /= 1 then
--               Interpret_Template (Labels & "case[@ !]@ is$" & "!" & "end case");
--
--            else
--               Interpret_Template;
--            end if;
--         end Do_Case_Statement;
--
--         procedure Do_Component_Clause is
--            --  We use "&" to right-justify the three expressions X, Y, and Z in
--            --  "at X range Y .. Z". We need to lift the Y and Z expressions up so
--            --  they appear at the same level as X, so the Tree and Parent of the
--            --  "&" will match that of the following "^". The Index_In_Lines must
--            --  also match. The end result will be something like:
--            --     Thing   at 0 range   0 ..  127;
--            --     Thing_2 at 0 range 128 .. 1023;
--
--            pragma Assert
--              (Subtree (Tree, 3).Kind = A_Discrete_Simple_Expression_Range);
--            Subts : constant Ada_Tree_Array :=
--              Subtrees (Tree) (1 .. 2) & Subtrees (Subtree (Tree, 3));
--            pragma Assert (Subts'Last = 4);
--            Cc_Templ : constant Ada_Template :=
--              "! ^at &2! ^2range [@&3! ^3..[@ &4!^4]]";
--         begin
--            Interpret_Template (Cc_Templ, Subts);
--         end Do_Component_Clause;
--
--         procedure Do_Constrained_Array_Definition is
--         begin
--            case Subtree (Subtree (Tree, 1), 1).Kind is
--               when A_Range_Attribute_Reference | A_Simple_Expression_Range =>
--                  Interpret_Template (Constrained_Array_Definition_Alt_Templ_1);
--               when others =>
--                  Interpret_Template (Constrained_Array_Definition_Alt_Templ_2);
--            end case;
--         end Do_Constrained_Array_Definition;
--
--         procedure Do_Def_Name is
--            Kind : Ada_Tree_Kind;
--         begin
--            if Tree.Kind = A_Defining_Expanded_Name then
--               Interpret_Template ("![@.!]");
--            else
--               --  Odd special case for task and protected bodies: If we have
--               --  "task body T is...", what casing rule should be used for "T"?
--               --  If the spec is a task type declaration, we should use the rule
--               --  for types, but if it's a single task declaration, we should use
--               --  the rule for other names. This is only relevant if
--               --  PP_Type_Casing /= PP_Name_Casing, which is hardly ever the
--               --  case.
--
--               if Decl_Of_Def (Symtab, Tree).Kind in
--                 A_Task_Body_Declaration | A_Protected_Body_Declaration
--               then
--                  Kind := Decl_Of_Def_Kind (Symtab, Spec_Of_Body (Symtab, Tree));
--               else
--                  Kind := Decl_Of_Def_Kind (Symtab, Tree);
--               end if;
--
--               Put ("\1",
--                    Id_With_Casing (Tree.Def_Name, Kind, Is_Predef => False));
--            end if;
--         end Do_Def_Name;
--
--         procedure Do_Extended_Return_Statement is
--         begin
--            --  If there are no statements or exception handlers, use short form
--
--            if Subtree_Count (Subtree (Tree, 3)) = 0
--              and then Subtree_Count (Subtree (Tree, 4)) = 0
--            then
--               Interpret_Template (Extended_Return_Statement_Alt_Templ);
--            else
--               Interpret_Template;
--            end if;
--         end Do_Extended_Return_Statement;
--
--         procedure Do_Extension_Aggregate is
--         begin
--            if Subtree_Count (Subtree (Tree, 2)) = 0 then
--               Interpret_Template ("@(! with @" & "null record)!");
--
--            else
--               Interpret_Template;
--            end if;
--         end Do_Extension_Aggregate;
--
--         type Precedence_Level is range 1 .. 7;
--         function Precedence (Expr : Ada_Tree) return Precedence_Level;
--
--         function Precedence (Expr : Ada_Tree) return Precedence_Level is
--         begin
--            case Expr.Kind is
--   --  ???Don't treat membership tests as operators, for now
--   --            when An_In_Membership_Test | A_Not_In_Membership_Test =>
--   --               return 1;
--               when An_And_Then_Short_Circuit | An_Or_Else_Short_Circuit =>
--                  return 2;
--
--               when A_Function_Call =>
--                  --  Binary operator using operator notation
--
--                  if Subtree (Expr, 3).Kind /= An_Is_Prefix_Call
--                    and then Subtree_Count (Subtree (Expr, 2)) /= 1
--                  then
--                     pragma Assert
--                       (Subtree (Expr, 4).Kind /= An_Is_Prefix_Notation);
--                     pragma Assert (Subtree_Count (Subtree (Expr, 2)) = 2);
--                     case Subtree (Expr, 1).Kind is
--                        when An_And_Operator | An_Or_Operator | An_Xor_Operator =>
--                           return 2; -- same as 'and then' and 'or else'
--
--                        when An_Equal_Operator             |
--                          A_Not_Equal_Operator             |
--                          A_Less_Than_Operator             |
--                          A_Less_Than_Or_Equal_Operator    |
--                          A_Greater_Than_Operator          |
--                          A_Greater_Than_Or_Equal_Operator =>
--                           return 3;
--
--                        when A_Plus_Operator     |
--                          A_Minus_Operator       |
--                          A_Concatenate_Operator =>
--                           return 4;
--
--                        when A_Multiply_Operator |
--                          A_Divide_Operator      |
--                          A_Mod_Operator         |
--                          A_Rem_Operator         =>
--                           return 5;
--
--                        when An_Exponentiate_Operator =>
--                           return 6;
--
--                        when others =>
--                           raise Program_Error;
--                     end case;
--
--                  --  Unary operator or normal function-call notation
--
--                  else
--                     return 7;
--                  end if;
--
--               --  Assume anything else is a primary (highest precedence)
--
--               when others =>
--                  return 7;
--            end case;
--         end Precedence;
--
--         function Get_Arg (Expr : Ada_Tree; N : Query_Index) return Ada_Tree;
--
--         function Get_Arg (Expr : Ada_Tree; N : Query_Index) return Ada_Tree is
--            Assoc : constant Ada_Tree := Subtree (Subtree (Expr, 2), N);
--            pragma Assert (Assoc.Kind = A_Parameter_Association);
--            function Is_Positional
--              (Assoc : Ada_Tree)
--               return  Boolean is
--              (Subtree (Assoc, 1).Kind = Not_An_Element);
--            pragma Assert (Is_Positional (Assoc));
--
--         begin
--            return Subtree (Assoc, 2);
--         end Get_Arg;
--
--         function Make_Op (Expr : Ada_Tree) return Ada_Tree;
--         --  Create operator node. This is a separate function to reduce stack
--         --  usage (for example long strings of "&" can cause deep recursion).
--
--         function Make_Op (Expr : Ada_Tree) return Ada_Tree is
--         begin
--            return Result : constant Ada_Tree := Make (An_Identifier) do
--               case Expr.Kind is
--                  when A_Function_Call =>
--                     declare
--                        Q_Op_Sym : constant String :=
--                          To_Lower (Str (Subtree (Expr, 1).Ref_Name).S);
--                        Un_Q : constant String (1 .. Q_Op_Sym'Length - 2) :=
--                          Q_Op_Sym (2 .. Q_Op_Sym'Last - 1);
--                     --  Strip off quotes
--                     begin
--                        Result.Ref := Intern (Un_Q);
--                     end;
--
--                  when An_And_Then_Short_Circuit =>
--                     Result.Ref := Name_And_Then;
--
--                  when An_Or_Else_Short_Circuit =>
--                     Result.Ref := Name_Or_Else;
--
--                  when others =>
--                     raise Program_Error;
--               end case;
--               Result.Ref_Name := Result.Ref;
--            end return;
--         end Make_Op;
--
--         procedure Do_Unary_Operator (Expr : Ada_Tree);
--
--         procedure Do_Binary_Operator
--           (Expr      : Ada_Tree;
--            Is_Right  : Boolean;
--            Cur_Level : Nesting_Level);
--         --  Also handles some things that look like operators, like "and then".
--         --  Is_Right is True if Expr is the right-hand argument of an outer
--         --  binary operator. Otherwise (Expr is the left-hand argument, or Expr's
--         --  parent is something else, like a parenthesized expression), Is_Right
--         --  is False.
--
--         function Is_Bin_Op (Expr : Ada_Tree) return Boolean;
--
--         procedure Do_Unary_Operator (Expr : Ada_Tree) is
--            Op       : constant Ada_Tree       := Make_Op (Expr);
--            Arg1     : constant Ada_Tree       := Get_Arg (Expr, 1);
--         begin
--            --  First we have a special case for the Depends aspect specification.
--            --  We want to pretend that "=>+" is an operator, so we print:
--            --   "Depends => (A =>+ B)" instead of "Depends => (A => +B)".
--            --  We don't bother with this for pragma Depends, because that's
--            --  mainly for the compiler's implementation of the aspect, so we
--            --  don't expect it to be used much.
--
--            if Ancestor_Tree (4).Kind = An_Aspect_Specification
--              and then Subtree (Ancestor_Tree (4), 1).Ref_Name = Name_Depends
--            then
--               pragma Assert (Subtree (Expr, 1).Kind = A_Unary_Plus_Operator);
--               pragma Assert
--                 (Slice (Out_Buf, Point (Out_Buf) - 4, Point (Out_Buf) - 1)
--                    = " => ");
--               declare
--                  Subtrees : constant Ada_Tree_Array := (1 => Arg1);
--               begin
--                  Replace_Previous (Out_Buf, '+');
--                  Interpret_Template (" !", Subtrees);
--               end;
--
--            --  No special "Depends" case. Put a space after the operator,
--            --  except for "+" and "-".
--
--            else
--               declare
--                  Subtrees : constant Ada_Tree_Array := (Op, Arg1);
--               begin
--                  if Subtree (Expr, 1).Kind in
--                    A_Unary_Plus_Operator | A_Unary_Minus_Operator
--                  then
--                     Interpret_Template ("!!", Subtrees);
--                  else
--                     Interpret_Template ("! !", Subtrees);
--                  end if;
--               end;
--            end if;
--         end Do_Unary_Operator;
--
--         function Is_Bin_Op (Expr : Ada_Tree) return Boolean is
--         begin
--            case Expr.Kind is
--               when A_Function_Call =>
--                  return Subtree (Expr, 3).Kind /= An_Is_Prefix_Call
--                    and then Subtree_Count (Subtree (Expr, 2)) = 2;
--
--               when An_And_Then_Short_Circuit | An_Or_Else_Short_Circuit =>
--                  return True;
--
--               when others =>
--                  return False;
--            end case;
--         end Is_Bin_Op;
--
--         procedure Do_Binary_Operator
--           (Expr      : Ada_Tree;
--            Is_Right  : Boolean;
--            Cur_Level : Nesting_Level)
--         is
--            Is_Short_C : constant Boolean :=
--              Expr.Kind in An_And_Then_Short_Circuit | An_Or_Else_Short_Circuit;
--            Is_Expon : constant Boolean := -- True for "**"
--              (Expr.Kind in A_Function_Call
--               and then Subtree (Expr, 1).Kind = An_Exponentiate_Operator);
--            Op          : constant Ada_Tree := Make_Op (Expr);
--            Arg1, Arg2  : Ada_Tree;
--            Arg1_Higher : Boolean; -- Arg1 is higher precedence than Expr
--
--         --  Calculate template fragments for the args (Arg1/2_T), that indent
--         --  if the arg is a higher precedence binary operator than the whole
--         --  expression.
--
--         --  Start of processing for Do_Binary_Operator
--
--         begin
--            if Is_Short_C then
--               Arg1 := Subtree (Expr, 1);
--               Arg2 := Subtree (Expr, 2);
--
--            else -- function call
--               Arg1 := Get_Arg (Expr, 1);
--               Arg2 := Get_Arg (Expr, 2);
--            end if;
--
--            --  The arguments can't have lower precedence than the expression as
--            --  a whole; that's what precedence means -- you need parens to put
--            --  a "+" inside a "*". The right-hand argument can't have equal
--            --  precedence, because Ada has no right-associative binary operators.
--
--            pragma Assert (Precedence (Arg1) >= Precedence (Expr));
--            pragma Assert (Precedence (Arg2) > Precedence (Expr));
--
--            Arg1_Higher := Precedence (Arg1) > Precedence (Expr);
--
--            --  The recursive calls to Do_Binary_Operator below bypass the
--            --  normal recursion via Subtree_To_Ada, so we need to pass along the
--            --  Cur_Level to Interpret_Template. When we reach something that's
--            --  not a binary op, we switch back to the normal recursion via
--            --  Interpret_Template on the Arg. We split lines after the
--            --  operator symbol, as in:
--            --     Some_Long_Thing +
--            --     Some_Other_Long_Thing
--            --  except in the case of short circuits:
--            --     Some_Long_Thing
--            --     and then Some_Other_Long_Thing
--            --  The --split-line-before-op switch causes all operators to be
--            --  treated like short circuits in this regard.
--            --
--            --  All operators are surrounded by blanks, except for "**":
--            --     Max : constant := 2**31 - 1;
--
--            if Is_Bin_Op (Arg1) then
--               if Is_Right and then Arg1_Higher then
--                  Interpret_Template ("[@", Empty_Tree_Array, Cur_Level);
--               end if;
--               Do_Binary_Operator
--                 (Arg1,
--                  Is_Right  => Is_Right,
--                  Cur_Level => Cur_Level + (if Arg1_Higher then 1 else 0));
--               if Is_Right and then Arg1_Higher then
--                  Interpret_Template ("]", Empty_Tree_Array, Cur_Level);
--               end if;
--
--            else
--               Interpret_Template
--                 ("!",
--                  Subtrees  => (1 => Arg1),
--                  Cur_Level => Cur_Level);
--            end if;
--
--            if Is_Short_C or Arg (Cmd, Split_Line_Before_Op) then
--               Interpret_Template ("@", Empty_Tree_Array, Cur_Level);
--            end if;
--            Interpret_Template
--              ((if Is_Expon then "!" else " ! "), -- no blanks for "**"
--               Subtrees  => (1 => Op),
--               Cur_Level => Cur_Level);
--            if not (Is_Short_C or Arg (Cmd, Split_Line_Before_Op)) then
--               Interpret_Template ("@", Empty_Tree_Array, Cur_Level);
--            end if;
--
--            if Is_Bin_Op (Arg2) then
--               Interpret_Template ("[@", Empty_Tree_Array, Cur_Level + 1);
--               Do_Binary_Operator
--                 (Arg2,
--                  Is_Right  => True,
--                  Cur_Level => Cur_Level + 1);
--               Interpret_Template ("]", Empty_Tree_Array, Cur_Level + 1);
--
--            else
--               Interpret_Template
--                 ("!",
--                  Subtrees  => (1 => Arg2),
--                  Cur_Level => Cur_Level + 1);
--            end if;
--         end Do_Binary_Operator;
--
--         procedure Do_Function_Call is
--         begin
--            --  Note: Is_Prefix_Notation is for Object.Operation(...) notation,
--            --  whereas Is_Prefix_Call is for anything that's not an operator
--            --  notation call. Thus Is_Prefix_Call is True for "&"(X, Y), and
--            --  False for X&Y.
--
--            if Subtree (Tree, 4).Kind = An_Is_Prefix_Notation then
--               pragma Assert (Subtree (Tree, 3).Kind = An_Is_Prefix_Call);
--               Prefix_Notation_Call
--                 (Label_Names => Empty (A_Defining_Name_List),
--                  Callee      => Subtree (Tree, 1),
--                  Actuals     => Subtree (Tree, 2));
--
--            --  Determine whether to use operator notation, like X+Y instead of
--            --  "+"(X,Y). We can use operator notation if it's an operator call,
--            --  and the argument(s) are in positional notation (not named). ???We
--            --  must use operator notation for "/=", to work around compiler bug.
--            --  In some cases, "/="(X, Y) doesn't work (on access types?), so we
--            --  generate (X /= Y) instead.
--
--            --  We don't want to translate "&" (STRING'("AB"), STRING'("CDEF"))(5)
--            --  /= CHARACTER'('E') into ((STRING'("AB") & STRING'("CDEF"))(5)
--            --  /= CHARACTER'('E')) because an operator-notation call is not a
--            --  name, and therefore cannot be used as the prefix of an indexed
--            --  component.
--
--            elsif Subtree (Tree, 3).Kind = An_Is_Prefix_Call then
--               if Past_Call_Threshold (Subtree (Tree, 2)) then
--                  Interpret_Template (Hard_Breaks_For_Call (Tree.Kind));
--               else
--                  Interpret_Template; -- normal "F (X)" notation
--               end if;
--
--            --  Operator notation:
--
--            else
--               pragma Assert
--                 (Subtree (Tree, 1).Kind in Flat_Operator_Symbol_Kinds);
--               pragma Assert (Subtree_Count (Subtree (Tree, 2)) in 1 .. 2);
--
--               --  Unary operator
--
--               if Subtree_Count (Subtree (Tree, 2)) = 1 then
--                  Do_Unary_Operator (Tree);
--
--               --  Binary operator
--
--               else
--                  Do_Binary_Operator
--                    (Tree,
--                     Is_Right  => False,
--                     Cur_Level => Cur_Level);
--               end if;
--            end if;
--         end Do_Function_Call;
--
--         procedure Do_List is
--         --  This formats the list elements with a hard line break in between. It
--         --  is called when a "!" in a template refers to a list subtree. If you
--         --  don't want this formatting, you must use "?" instead of "!". See,
--         --  for example, the template for An_If_Expression, where we want soft
--         --  line breaks in between paths. Sometimes this is called for a list
--         --  of one element, in which case the Between doesn't matter (e.g.
--         --  Defining_Name_List, where there is only one).
--         begin
--            Subtrees_To_Ada (Tree, Pre => "", Between => "$", Post => "");
--         end Do_List;
--
--         procedure Do_Literal is
--            S : constant W_Str := To_W_Str (Tree.Lit_Val);
--
--            function Last_Digit
--              (First : Positive; Based : Boolean) return Positive;
--            --  Returns the index of the last digit in S starting at
--            --  First
--
--            procedure Put_With_Underscores
--              (Part : W_Str; Grouping : Positive; Int : Boolean);
--            --  Part is the integer part (before the '.', if any) or the
--            --  fractional part (after the '.'). Int is True for the integer part.
--            --  For example, for "16#12345.67890#e2", this will be called for Part
--            --  = "12345" and Int = True, then for Part = "67890" and Int = False.
--            --  We want to get "16#1_2345.6789_0#e2" (assuming Grouping = 4).
--
--            procedure Put_With_Underscores
--              (Part : W_Str; Grouping : Positive; Int : Boolean)
--            is
--               Count : Natural := (if Int then Part'Length else 0);
--               Inc : constant Integer := (if Int then -1 else 1);
--               --  For the integer part, we count downward from the Length; for
--               --  the fractional part, we count upward from zero. If Count is
--               --  divisible by Grouping, the next character should be preceded by
--               --  an underscore, except there is never a leading underscore.
--            begin
--               for J in Part'Range loop
--                  if J /= Part'First and then Count mod Grouping = 0 then
--                     Put_Char ('_');
--                  end if;
--                  Put_Char (Part (J));
--                  Count := Count + Inc;
--               end loop;
--            end Put_With_Underscores;
--
--            function Last_Digit
--              (First : Positive; Based : Boolean) return Positive
--            is
--            begin
--               for J in First .. S'Last loop
--                  if Is_Digit (S (J)) then
--                     null;
--                  elsif Based and then Is_Letter (S (J)) then
--                     null;
--                  else
--                     return J - 1;
--                  end if;
--               end loop;
--               return S'Last;
--            end Last_Digit;
--
--         --  Start of processing for Do_Literal
--
--         begin
--            pragma Assert (Check_Whitespace);
--            Check_Whitespace := False;
--
--            --  In most cases, we simply print out S. All of the complicated code
--            --  below is for the --decimal-grouping and --based-grouping
--            --  switches. If --decimal-grouping was used to specify a nonzero
--            --  value, and we have a numeric literal without a base, and that
--            --  literal contains no underscores, we insert underscores. Similarly
--            --  for --based-grouping. A based literal is one containing "#" or
--            --  ":"; note that "10#...#" is considered based, not decimal.
--
--            case Tree.Kind is
--               when A_String_Literal =>
--                  Put ("\1", S);
--
--               when An_Integer_Literal | A_Real_Literal =>
--                  if Arg (Cmd, Decimal_Grouping) = 0
--                    and then Arg (Cmd, Based_Grouping) = 0
--                  then
--                     Put ("\1", S);
--                  else
--                     declare
--                        Sharp : constant Natural :=
--                          (if Find (S, "#") /= 0 then Find (S, "#")
--                           else Find (S, ":"));
--                        Underscore : constant Natural := Find (S, "_");
--
--                        Grouping : constant Natural :=
--                          (if Underscore /= 0 then 0
--                           elsif Sharp = 0 then Arg (Cmd, Decimal_Grouping)
--                           else Arg (Cmd, Based_Grouping));
--
--                        Int_First, Int_Last, Frac_First, Frac_Last : Natural;
--                        --  These point to the slices of the literal that should
--                        --  have underscores inserted. For example:
--                        --     For 12345 or 12345E6:
--                        --       S (Int_First .. Int_Last) = "12345"
--                        --     For 12345.6789 or 16#12345.6789#E-3:
--                        --       S (Int_First .. Int_Last) = "12345", and
--                        --       S (Frac_First .. Frac_Last) = "6789"
--                     begin
--                        if Grouping = 0 then
--                           Put ("\1", S);
--                        else
--                           Int_First := Sharp + 1;
--                           Int_Last :=
--                             Last_Digit (Int_First, Based => Sharp /= 0);
--                           Put ("\1", S (1 .. Sharp));
--                           Put_With_Underscores
--                             (S (Int_First .. Int_Last),
--                              Grouping, Int => True);
--                           if Tree.Kind = An_Integer_Literal then
--                              Put ("\1", S (Int_Last + 1 .. S'Last));
--                           else
--                              Frac_First := Int_Last + 2; -- skip '.'
--                              Frac_Last := Last_Digit
--                                (Frac_First, Based => Sharp /= 0);
--                              pragma Assert
--                                (S (Int_Last + 1 .. Frac_First - 1) = ".");
--                              Put_Char ('.');
--                              Put_With_Underscores
--                                (S (Frac_First .. Frac_Last),
--                                 Grouping, Int => False);
--                              Put ("\1", S (Frac_Last + 1 .. S'Last));
--                           end if;
--                        end if;
--                     end;
--                  end if;
--
--               when others => raise Program_Error;
--            end case;
--
--            Check_Whitespace := True;
--         end Do_Literal;
--
--         procedure Do_Null_Statement is
--         begin
--            --  If a label comes at the end of a statement list, as allowed in Ada
--            --  2012, ASIS inserts an extra implicit null statement to hang the
--            --  label off of. We don't want to print that statement, because
--            --  it wasn't in the source code. We can detect such implicit null
--            --  statements by checking for a nil Sloc. We also need to suppress
--            --  the ";" that comes after the implicit 'null', which is the purpose
--            --  of Implicit_Null_Statement_Seen. We set that flag True here, and
--            --  the very next template character seen by Interpret_Template will
--            --  be that ";", so Interpret_Template will suppress the ";" and reset
--            --  Implicit_Null_Statement_Seen to False.
--
--            if Subtree_Count (Subtree (Tree, 1)) /= 0
--              and then Asis.Text.Is_Nil (Tree.Sloc)
--            then
--               Interpret_Template (Labels);
--               Implicit_Null_Statement_Seen := True;
--
--            else
--               Interpret_Template;
--            end if;
--         end Do_Null_Statement;
--
--         procedure Do_Ordinary_Type_Declaration is
--         begin
--            if Subtree (Tree, 3).Kind in
--                A_Derived_Record_Extension_Definition |
--                  A_Record_Type_Definition |
--                  A_Tagged_Record_Type_Definition |
--                  An_Access_To_Procedure |
--                  An_Access_To_Protected_Procedure |
--                  An_Access_To_Function |
--                  An_Access_To_Protected_Function
--            then
--               Interpret_Template ("type !! is !" & Aspects);
--            --  Record_Definition or other subtree will take care of new lines.
--            --  ???It might be better to have a *weak* newline, though.
--            else
--               Interpret_Template;
--            end if;
--         end Do_Ordinary_Type_Declaration;

         procedure Do_Others is
            use ASIS_UL.Dbg_Out;
         begin
            if Template_Table (Tree.Kind) = null then
               ASIS_UL.Dbg_Out.Output_Enabled := True;
               Put ("null templ:\1", Capitalize (Tree.Kind'Img));
               Subtrees_To_Ada (Tree, Pre => "{", Between => "|", Post => "}");
--               raise Program_Error;
            else
               Interpret_Template;
            end if;
         end Do_Others;

--         procedure Do_Parameter_Specification is
--         begin
--            Subtrees_To_Ada
--              (Subtree (Tree, Index),
--               Pre     => "",
--               Between => ",@ ",
--               Post    => "");
--            Interpret_Template
--              (Parameter_Specification_Alt_Templ,
--               Subtrees => Empty_Tree_Array);
--
--            case Tree.Kind is
--               when A_Parameter_Specification =>
--                  Index := Index + 1;
--
--                  if Subtree (Tree, Index).Kind /=
--                    Not_An_Element
--                  then -- "aliased"
--                     Subtree_To_Ada (Subtree (Tree, Index), Cur_Level + 1, Index);
--                     Put (" ");
--                  end if;
--
--               when A_Formal_Object_Declaration =>
--                  null; -- A_Formal_Object_Declaration doesn't have "aliased"
--
--               when others =>
--                  raise Program_Error;
--            end case;
--
--            if Tree.Mode in An_In_Mode | An_In_Out_Mode then
--               Put ("in ");
--            end if;
--            Interpret_Template ("^2", Subtrees => Empty_Tree_Array);
--            if Tree.Mode in An_Out_Mode | An_In_Out_Mode then
--               Put ("out ");
--            end if;
--            Interpret_Template ("^3", Subtrees => Empty_Tree_Array);
--
--            Index := Index + 1;
--
--            if Subtree (Tree, Index).Kind /= Not_An_Element then -- "not null"
--               Subtree_To_Ada (Subtree (Tree, Index), Cur_Level + 1, Index);
--               Put (" ");
--            end if;
--
--            Index := Index + 1;
--            Subtree_To_Ada (Subtree (Tree, Index), Cur_Level + 1, Index);
--
--            Index := Index + 1;
--            if Subtree (Tree, Index).Kind /= Not_An_Element then
--               Interpret_Template
--                 (" ^4:=[@ !]",
--                  Subtrees => (1 => Subtree (Tree, Index)));
--            end if;
--         end Do_Parameter_Specification;
--
--         procedure Do_Pragma is
--         begin
--            Put
--              ("pragma \1",
--               Id_With_Casing (Tree.Pragma_Name, Tree.Kind, Is_Predef => False));
--            Interpret_Template (Pragma_Alt_Templ);
--         end Do_Pragma;
--
--         procedure Do_Procedure_Call_Statement is
--         begin
--            if Tree.Kind = A_Procedure_Call_Statement
--              and then Subtree (Tree, 4).Kind = An_Is_Prefix_Notation
--            then
--               Prefix_Notation_Call
--                 (Label_Names => Subtree (Tree, 1),
--                  Callee      => Subtree (Tree, 2),
--                  Actuals     => Subtree (Tree, 3));
--            elsif Past_Call_Threshold (Subtree (Tree, 3)) then
--               Interpret_Template (Hard_Breaks_For_Call (Tree.Kind));
--            else
--               Interpret_Template;
--            end if;
--         end Do_Procedure_Call_Statement;
--
--         procedure Do_Qualified_Expression is
--         begin
--            if Subtree (Tree, 2).Kind in
--                A_Record_Aggregate |
--                  An_Extension_Aggregate |
--                  A_Positional_Array_Aggregate |
--                  A_Named_Array_Aggregate
--            then
--               Interpret_Template ("!'[@!]");
--            --  If the thing after the ' is an aggregate, we leave out the
--            --  parentheses here, because the aggregate will insert them. We
--            --  want T'(X, Y, Z), not T'((X, Y, Z)).
--
--            else
--               Interpret_Template;
--            end if;
--         end Do_Qualified_Expression;
--
--         procedure Do_Record_Aggregate is
--         begin
--            if Subtree_Count (Subtree (Tree, 1)) = 0 then
--               Interpret_Template ("@(null record)!");
--            else
--               Interpret_Template;
--            end if;
--         end Do_Record_Aggregate;
--
--         procedure Do_Single_Task_Declaration is
--         begin
--            --  For single task declarations, use short form if
--            --  Object_Declaration_View is Nil
--
--            if Is_Nil (Subtree (Tree, 4)) then
--               Interpret_Template ("task !" & Aspects & "!!");
--
--            else
--               Interpret_Template;
--            end if;
--         end Do_Single_Task_Declaration;
--
--         procedure Do_Subp_Decl
--           (Is_Function, Is_Body : Boolean;
--            Params_Query         : Structural_Queries)
--            --  Params_Query is the query for getting the formal parameters
--         is
--            --  This is for subprogram declarations and the like -- everything
--            --  that has a formal parameter list.
--
--            Param_Count : constant Query_Count :=
--              Subtree_Count (Get (Tree, Params_Query)) +
--              Boolean'Pos (Is_Function); -- Add one extra for function result
--         begin
--            if Param_Count > Query_Count (Arg (Cmd, Par_Threshold)) then
--               Interpret_Template
--                 (Subp_Decl_With_Hard_Breaks
--                    (Tree,
--                     Is_Function,
--                     Is_Body));
--            else
--               Interpret_Template;
--            end if;
--         end Do_Subp_Decl;
--
--         procedure Do_Subtype_Indication is
--         begin
--            if Subtree (Tree, 4).Kind in
--                A_Range_Attribute_Reference |
--                  A_Simple_Expression_Range
--            then
--               Interpret_Template ("?~~ ~?~~ ~!? range ~~~");
--            elsif Arg (Cmd, Rm_Style_Spacing)
--              and then Subtree (Tree, 4).Kind = An_Index_Constraint
--            then
--               Interpret_Template ("?~~ ~?~~ ~!?~~~");
--            else
--               Interpret_Template ("?~~ ~?~~ ~!? ~~~");
--            end if;
--         end Do_Subtype_Indication;
--
--         procedure Do_Task_Type_Declaration is
--         begin
--            --  For task type declarations, use short form if
--            --  Type_Declaration_View is Nil
--
--            if Is_Nil (Subtree (Tree, 5)) then
--               Interpret_Template ("task type !!" & Aspects & "!!");
--
--            else
--               Interpret_Template;
--            end if;
--         end Do_Task_Type_Declaration;

         procedure Do_Usage_Name is
--            --  The following works around a compiler limitation related to
--            --  'Elab_Spec and 'Elab_Body attributes. For something like
--            --  "Ada.Text_IO'Elab_Spec", the compiler does not analyze the prefix
--            --  "Ada.Text_IO", so it looks like a name that doesn't denote
--            --  anything, like an identifier specific to a pragma. Setting
--            --  Elab_Spec_Seen to True tells Id_With_Casing to treat it like a
--            --  normal name (it really DOES denote something).
--            Elab_Spec_Seen : Boolean          := False;
--            N              : Tree_Stack_Index := Last_Index (Tree_Stack);
--            P              : Ada_Tree_Base;
--            A              : Symbol;
         begin
--            while N > 1 and then Tree_Stack (N - 1).Kind = A_Selected_Component
--            loop
--               N := N - 1;
--            end loop;
--            if N > 1 then
--               P := Tree_Stack (N - 1);
--               if P.Kind = An_Implementation_Defined_Attribute then
--                  A := Subtree (P, 2).Ref_Name;
--                  if (A in Name_Elab_Spec | Name_Elab_Body)
--                    and then Subtree (P, 1) = Tree_Stack (N)
--                  then
--                     Elab_Spec_Seen := True;
--                  end if;
--               end if;
--            end if;
--            --  End special handling for 'Elab_Spec and 'Elab_Body
--
--            Put
--              ("\1",
--               Id_With_Casing
--                 (Tree.Ref_Name,
--                  Tree.Decl_Kind,
--                  Tree.Is_Predef,
--                  Use_Name_Casing_For_Nils => Elab_Spec_Seen));
            Put
              ("\1",
               Id_With_Casing
                 (W_Intern (Id_Name (Tree)),
                  Kind => Ada_Abort_Statement,
                  Is_Predef => False,
                  Use_Name_Casing_For_Nils => False));
         end Do_Usage_Name;

      --  Start of processing for Subtree_To_Ada

      begin
         if Tree = null then -- ????
            return;
         end if;

         Append (Tree_Stack, Tree); -- push

         Maybe_Blank_Line;

         case Tree.Kind is
            when Ada_Compilation_Unit =>
               Do_Compilation_Unit;

--            when A_Comment =>
--               Do_Comment;
--
--            when Def_Names =>
--               Do_Def_Name;
--
            when Ada_Identifier => -- Usage_Names =>
               Do_Usage_Name;
--
--            when An_Integer_Literal | A_Real_Literal | A_String_Literal =>
--               Do_Literal;
--
--            when Flat_Pragma_Kinds =>
--               Do_Pragma;
--
--            when A_Null_Statement =>
--               Do_Null_Statement;
--
--            when An_Ordinary_Type_Declaration =>
--               Do_Ordinary_Type_Declaration;
--
--            when A_Procedure_Call_Statement | An_Entry_Call_Statement =>
--               Do_Procedure_Call_Statement;
--
--            when A_Function_Call =>
--               Do_Function_Call;
--
--            when An_And_Then_Short_Circuit | An_Or_Else_Short_Circuit =>
--               Do_Binary_Operator
--                 (Tree,
--                  Is_Right  => False,
--                  Cur_Level => Cur_Level);
--
--            when A_Task_Type_Declaration =>
--               Do_Task_Type_Declaration;
--
--            when A_Single_Task_Declaration =>
--               Do_Single_Task_Declaration;
--
--            when A_Pragma_Argument_Association |
--              A_Discriminant_Association       |
--              A_Record_Component_Association   |
--              An_Array_Component_Association   |
--              A_Parameter_Association          |
--              A_Generic_Association            =>
--               Do_Association;
--
--            when Flat_Attribute_Reference_Kinds =>
--               Do_Attribute_Reference;
--
--            when A_Block_Statement =>
--               Do_Block_Statement;
--
--            when A_Subtype_Indication =>
--               Do_Subtype_Indication;
--
--            when A_Case_Path =>
--               Do_Case_Path;
--
--            when A_Case_Statement =>
--               Do_Case_Statement;
--
--            when A_Component_Clause =>
--               Do_Component_Clause;
--
--            when A_Constrained_Array_Definition     |
--              A_Formal_Constrained_Array_Definition =>
--               Do_Constrained_Array_Definition;
--
--            when An_Extended_Return_Statement =>
--               Do_Extended_Return_Statement;
--
--            when An_Accept_Statement =>
--               Do_Accept_Statement;
--
--            when A_Positional_Array_Aggregate |
--                A_Named_Array_Aggregate =>
--               Do_Array_Aggregate;
--
--            when A_Qualified_Expression =>
--               Do_Qualified_Expression;
--
--            when A_Record_Aggregate =>
--               Do_Record_Aggregate;
--
--            when An_Extension_Aggregate =>
--               Do_Extension_Aggregate;
--
--            when A_Parameter_Specification | A_Formal_Object_Declaration =>
--               Do_Parameter_Specification;
--
--            when A_Procedure_Declaration       |
--              A_Null_Procedure_Declaration     |
--              A_Procedure_Renaming_Declaration |
--              An_Entry_Declaration             |
--              A_Generic_Procedure_Declaration  |
--              A_Formal_Procedure_Declaration   |
--              A_Procedure_Body_Stub            =>
--               --  An_Accept_Statement goes through Do_Accept_Statement
--               Do_Subp_Decl
--                 (Is_Function  => False,
--                  Is_Body      => False,
--                  Params_Query => Parameter_Profile);
--
--            when A_Procedure_Body_Declaration |
--              An_Entry_Body_Declaration       =>
--               Do_Subp_Decl
--                 (Is_Function  => False,
--                  Is_Body      => True,
--                  Params_Query => Parameter_Profile);
--
--            when An_Access_To_Procedure                  |
--              An_Access_To_Protected_Procedure           |
--              An_Anonymous_Access_To_Procedure           |
--              An_Anonymous_Access_To_Protected_Procedure |
--              A_Formal_Access_To_Procedure               |
--              A_Formal_Access_To_Protected_Procedure     =>
--               Do_Subp_Decl
--                 (Is_Function  => False,
--                  Is_Body      => False,
--                  Params_Query => Access_To_Subprogram_Parameter_Profile);
--
--            when A_Function_Declaration          |
--              An_Expression_Function_Declaration |
--              A_Function_Renaming_Declaration    |
--              A_Generic_Function_Declaration     |
--              A_Formal_Function_Declaration      |
--              A_Function_Body_Stub               =>
--               Do_Subp_Decl
--                 (Is_Function  => True,
--                  Is_Body      => False,
--                  Params_Query => Parameter_Profile);
--
--            when A_Function_Body_Declaration  =>
--               Do_Subp_Decl
--                 (Is_Function  => True,
--                  Is_Body      => True,
--                  Params_Query => Parameter_Profile);
--
--            when An_Access_To_Function                  |
--              An_Access_To_Protected_Function           |
--              An_Anonymous_Access_To_Function           |
--              An_Anonymous_Access_To_Protected_Function |
--              A_Formal_Access_To_Function               |
--              A_Formal_Access_To_Protected_Function     =>
--               Do_Subp_Decl
--                 (Is_Function  => True,
--                  Is_Body      => False,
--                  Params_Query => Access_To_Subprogram_Parameter_Profile);
--
--            when Flat_List_Kinds =>
--               Do_List;
--
            when others =>
               Do_Others;
         end case;

         Delete_Last (Tree_Stack); -- pop
      end Subtree_To_Ada;

      procedure Convert_Tree_To_Ada (Tree : Ada_Tree) is
      begin
         Append_Line_Break
           (Hard     => True,
            Affects_Comments => True,
            Level    => 0,
--            Kind     => Not_An_Element,
            Kind     => Ada_Abort_Statement, -- ????
            Template => Name_Empty);
         pragma Assert (Check_Whitespace);
         Subtree_To_Ada (Tree, Cur_Level => 0, Index_In_Parent => 1);
         pragma Debug (Assert_No_Trailing_Blanks (To_W_Str (Out_Buf)));
         Append
           (Tabs,
            Tab_Rec'
              (Parent | Tree => null, Mark => Mark (Out_Buf, '$'), others => <>));
         --  Append a sentinel tab, whose Position is greater than any actual
         --  position. This ensures that as we step through Tabs, there is
         --  always one more.
         pragma Assert (Is_Empty (Tree_Stack));
         Reset (Out_Buf);
         pragma Assert (Cur_Indentation = 0);
      end Convert_Tree_To_Ada;

      procedure Assert_No_Trailing_Blanks (S : W_Str) is
      begin
         pragma Assert (S'First = 1);
         for X in 2 .. S'Last loop
            pragma Assert (if S (X) /= ' ' then not Is_Space (S (X)));
            if S (X) = NL then
               pragma Assert (S (X - 1) /= ' ');
            end if;
         end loop;
         pragma Assert (S (S'Last) = NL);
      end Assert_No_Trailing_Blanks;

   --  Start of processing for Tree_To_Ada_2

   begin
      if not Template_Table_Initialized then
         Init_Template_Table;
         Init_Pp_Off_And_On;
      end if;

      Convert_Tree_To_Ada (Root);
   end Tree_To_Ada_2;

   procedure Per_File_Action
     (Tool : in out Pp_Tool;
      Cmd : Command_Line;
      File_Name : String;
      Unit : Analysis_Unit)
   is
      pragma Unreferenced (Tool);

      use LAL_UL.Formatted_Output;

      Form_String : constant String := "WCEM=8";
      --  ????Should use Set_Form_String
      Write_BOM : Boolean := False;
      --  True if a byte order mark was found in the input file, in which case
      --  we want to write a BOM to the output file.

      Src_Buf : Buffer;
      --  Buffer containing the text of the original source file

      Output_Mode : constant Output_Modes := Get_Output_Mode (Cmd);
      Do_Diff : constant Boolean := Output_Mode in Replace_Modes;

      --  We initially write the output to Temp_Output_Name, then later rename it
      --  to Output_Name (except in Pipe mode). These are full pathnames. If we
      --  are overwriting the Source_Name, and it's a link link-->file, we want to
      --  overwrite file. But we put the temp file in the directory containing
      --  link, in case the directory containing file is not writable.

      function Get_Output_Name (Resolve_Links : Boolean) return String;
      function Get_Output_Name (Resolve_Links : Boolean) return String is
      begin
         pragma Assert (Environment.Initial_Dir = Current_Directory);
         return (case Output_Mode is
           when Pipe => "", -- not used
           when Output => Arg (Cmd, Output).all,
           when Output_Force => Arg (Cmd, Output_Force).all,
           when Replace_Modes => Normalize_Pathname
                                   (File_Name,
                                    Resolve_Links  => Resolve_Links,
                                    Case_Sensitive => True),

           when Default => File_Name & PP_Suffix,
           when Output_Directory =>
             Compose (Arg (Cmd, Output_Directory).all,
                      Simple_Name (File_Name)));
      end Get_Output_Name;

      Output_Name : constant String := Get_Output_Name (Resolve_Links => True);

      Temp_Output_Name : constant String :=
          (if Output_Mode = Pipe then "" -- means standard output
           else Get_Output_Name (Resolve_Links => False) & "__GNATPP-TEMP");

      Output_Written : Boolean := False;
      --  True if Tree_To_Ada wrote the output to Temp_Output_Name. It always
      --  does, except in Replace_Modes if the output would be identical to the
      --  input.

      procedure Write_File_Name_File;
      --  If the Output_Mode /= Pipe, and Output_Written is True, add a pair of
      --  lines to the file name file.

      procedure Write_File_Name_File is
         use Text_IO, GNAT.Lock_Files;
         Lock_File_Name : constant String := File_Name_File_Name.all & ".lock";

         procedure Do_Writes;
         --  Write the two file names to the file name file. This is split out
         --  into a procedure so we can call it with and without file locking, as
         --  appropriate.

         procedure Do_Writes is
            File_Name_File : File_Type;
         begin
            Open (File_Name_File,
                  Mode => Append_File,
                  Name => File_Name_File_Name.all);
            Put_Line (File_Name_File, Temp_Output_Name);
            Put_Line (File_Name_File, Output_Name);
            Close (File_Name_File);
         end Do_Writes;

      --  Start of processing for Write_File_Name_File

      begin
         if Output_Mode /= Pipe then
            --  In -r, -rf, and -rnb modes, if the output was identical to the
            --  input, Output_Written will be False, so there is no
            --  Temp_Output_Name file, so we don't move it in that case. This can
            --  also happen if the exception handler at the end of Tree_To_Ada is
            --  executed.

            pragma Assert
              (if Output_Mode not in Replace_Modes then Output_Written);
            if not Output_Written then
               return;
            end if;

--            if Mimic_gcc and then (Verbose_Mode or else Debug_Flag_V) then
--               Put_Line
--                 ((if Output_Mode in Replace_Modes
--                     then "updating "
--                     else "creating ") &
--                  (if Debug_Flag_V then Short_Source_Name (SF) else Output_Name));
--            end if;

            --  The temp file was created, so write a pair (Temp_Output_Name,
            --  Output_Name) of lines to the file name file, so Finalize will know
            --  to rename temp --> output. This is done under lock, in case this
            --  is an inner process of an incremental build, and the -j switch of
            --  the builder is used to invoke this in parallel.

            if Arg (Cmd, Outer_Parallel) then
               pragma Assert (Mimic_gcc (Cmd));
               Lock_File (Lock_File_Name, Wait => 0.1, Retries => 5 * 60 * 10);
               --  Retry for 5 minutes, every 100 milliseconds.
               declare
                  --  We create a dummy object whose finalization calls
                  --  Unlock_File, so we don't leave stale lock files around even
                  --  in case of unhandled exceptions.

                  type Dummy_Type is new Ada.Finalization.Limited_Controlled with
                    null record;
                  procedure Finalize (Ignore : in out Dummy_Type);
                  procedure Finalize (Ignore : in out Dummy_Type) is
                  begin
                     Unlock_File (Lock_File_Name);
                  end Finalize;

                  Dummy : Dummy_Type;

               begin
                  Do_Writes;
               end;

            --  Otherwise, it's safe to do the writes without any locking. We want
            --  to avoid locking when possible, because it reduces the likelihood
            --  of stale locks left lying around. It's a little more efficient,
            --  too.

            else
               Do_Writes;
            end if;
         end if;
      exception
         when Lock_Error =>
--            ASIS_UL.Output.Error ("cannot create " & Lock_File_Name);
--            ASIS_UL.Output.Error ("delete it by hand if stale");
            raise;
      end Write_File_Name_File;

      procedure Write_Str (Out_Elems : W_Str);
      procedure Write_Out_Buf (Out_Vec : Char_Vector);
      procedure Write_Src_Buf;
      --  Write_Out_Buf writes Out_Buf to the output. This is the normal
      --  case. Write_Src_Buf writes the Src_Buf to the output. Write_Str is the
      --  code common to both Write_Out_Buf and Write_Src_Buf.

      procedure Write_Str (Out_Elems : W_Str) is
         use Wide_Text_IO;
         Out_File : File_Type;
      begin
   --  ???
   --      if False then -- ???Messes up the diff's.
   --         Formatted_Output.Put
   --           ("--  ???Inner_Loop_Count = \1\n",
   --            Image (Inner_Loop_Count));
   --      end if;

         Output_Written := True;
         if Temp_Output_Name /= "" then
            --  If Temp_Output_Name = "", leave Current_Output pointing to
            --  standard output; otherwise point it to the file.
            Create (Out_File, Name => Temp_Output_Name,
                    Form => Form_String & ",Text_Translation=NO");
            Set_Output (Out_File);
         end if;

         --  If a BOM (byte order mark) was found in the input, we want to put it
         --  in the output.

         if Write_BOM then
   --         if Options.Output_Encoding /= System.WCh_Con.WCEM_UTF8 then
   --            raise Program_Error;
   --         end if;
            Put (W_Char'Val (16#FEFF#)); -- BOM as a wide character
         end if;

         --  We must call New_Line for LF's (at least for the last one in the
         --  Out_Elems), because otherwise Wide_Text_IO adds an annoying blank
         --  line to the end of the file. It would probably be better to avoid
         --  Wide_Text_IO altogether, but we're currently using it to do Unicode
         --  encoding transformations. Note that Put(CR) is not guaranteed to work
         --  by the Ada standard, but the GNAT implementation won't molest it.

         for C of Out_Elems loop
            if C = W_LF then
               New_Line;
            else
               Put (C);
            end if;
         end loop;

         if Temp_Output_Name /= "" then
            Close (Out_File);
            Set_Output (Ada.Wide_Text_IO.Standard_Output);
         end if;
      end Write_Str;

      procedure Write_Out_Buf (Out_Vec : Char_Vector) is
         pragma Assert (Point (Out_Buf) = 1);
         Out_Elems : W_Str renames Elems (Out_Vec)
           (2 .. Last_Index (Out_Vec)); -- 2 to skip initial NL
      begin
         --  In Do_Diff mode, don't write the output if it is identical to the
         --  input.

         if Do_Diff then
            declare
               Src_Elems : W_Str renames Elements (Src_Buf)
                 (1 .. Last_Position (Src_Buf));
            begin
               if Out_Elems = Src_Elems then
                  pragma Assert (not Output_Written);
                  return;
               end if;
            end;
         end if;

         Write_Str (Out_Elems);
      end Write_Out_Buf;

      procedure Write_Src_Buf is
         Out_Elems : W_Str renames Elements (Src_Buf)
           (1 .. Last_Position (Src_Buf));
      begin
         Write_Str (Out_Elems);
      end Write_Src_Buf;

      procedure Tree_To_Ada;
      procedure Tree_To_Ada is

         use Scanner;

      --  Start of processing for Tree_To_Ada

      begin
         if Debug_Mode then
            ASIS_UL.Dbg_Out.Output_Enabled := True;
         end if;

--         if not Template_Table_Initialized then
--            Init_Template_Table;
--            Init_Pp_Off_And_On;
--         end if;

         --  Note that if we're processing multiple files, we will get here multiple
         --  times, so we need to clear out data structures left over from last time.

         pragma Assert (Cur_Indentation = 0);
         Clear (All_Line_Breaks);
         Clear (Tabs);

         Get_Tokens (Src_Buf, Src_Tokens, LAL_UL.Ada_Version, Pp_Off_On_Delimiters);
         if Debug_Mode then
            Dbg_Out.Put ("Src_Tokens:\n");
            Put_Tokens (Src_Tokens);
            Dbg_Out.Put ("end Src_Tokens:\n");
         end if;

         Clear (Out_Buf);

         --  If --comments-only was specified, format the comments and quit

         if Arg (Cmd, Comments_Only) then
            Do_Comments_Only (Lines_Data, Src_Buf, Cmd);
         else
            --  Otherwise, convert the tree to text, and then run all the
            --  text-based passes.

            if True then
               Tree_To_Ada_2
                 (Root (Unit), Src_Buf, Out_Buf, Cmd, Is_PP => True);
               Post_Tree_Phases (Lines_Data, File_Name, Src_Buf, Cmd);
            else
               pragma Assert (Is_Empty (Out_Buf));
               pragma Assert (At_Beginning (Src_Buf));
               declare
                  Temp : W_Str renames
                    Elements (Src_Buf) (1 .. Last_Position (Src_Buf));
               begin
                  Insert_NL (Out_Buf);
                  Insert_Any (Out_Buf, Temp);
                  Reset (Out_Buf);
               end;
            end if;
         end if;

         --  Finally, print out the result to Current_Output

         declare
--            Out_Vec : constant Char_Vector := Remove_Extra_Line_Breaks;
            Out_Vec : constant Char_Vector := To_Vector (Out_Buf);
         begin
            Write_Out_Buf (Out_Vec);
         end;

      exception
         --  If we got an error, don't produce output

--         when Common.Fatal_Error =>
--            raise;

         when others =>
            --  In order to avoid damaging the user's source code, if there is a bug
            --  (like a token mismatch in Final_Check), we avoid writing the output
            --  file in Do_Diff mode; otherwise, we write the input to the output
            --  unchanged. This happens only in production builds.

            if Enable_Token_Mismatch then
               raise;
            else
               if Do_Diff then
                  pragma Assert (not Output_Written);
               else
                  if not At_Beginning (Src_Buf) then
                     while not At_End (Src_Buf) loop
                        Move_Forward (Src_Buf);
                     end loop;
                     Reset (Src_Buf);
                  end if;

                  Write_Src_Buf;
               end if;
            end if;
      end Tree_To_Ada;

      --  ???See ada_trees.pp for commented-out stuff below.

      procedure Maybe_To_Ada
--        (CU : Asis.Compilation_Unit;
--         Cmd         : LAL_UL.Command_Lines.Command_Line;
--         Output_Name : String;
--         Form_String : String;
--         Do_Diff : Boolean;
--         Output_Written : out Boolean;
         (To_Ada : Boolean);
      --  Helper for Asis_To_Ada. To_Ada is True for the first call, indicating
      --  we're going to generate Ada text; it is False for subsequent (recursive)
      --  calls, which merely generate trees for dependencies.

      procedure Maybe_To_Ada
--        (CU      : Asis.Compilation_Unit;
--         Cmd         : LAL_UL.Command_Lines.Command_Line;
--         Output_Name : String;
--         Form_String : String;
--         Do_Diff : Boolean;
--         Output_Written : out Boolean;
         (To_Ada : Boolean)
      is
--         Src_Tokens : Scanner.Token_Vector;
--         Src_Gen_Regions : aliased Scanner.Token_Vector;
--         Gen_Regions : Scanner.Token_Vector_Ptr := null;
--         --  Set to point to Src_Gen_Regions if necessary.
--
--         Write_BOM : Boolean;
--         --  True if BOM should be written to the output
--
--         procedure Walk_Dependencies (CU : Asis.Compilation_Unit);
--         --  Recursively walk compilation units this one depends on.
--
--         procedure Walk_Dependencies (CU : Asis.Compilation_Unit) is
--            Ignore : Boolean;
--         begin
--            Maybe_To_Ada (CU, Cmd, "no Output_Name", "no Form_String",
--                          False, Ignore, To_Ada => False);
--         end Walk_Dependencies;
--
--         Do_Dependencies : constant Boolean :=
--           PP_Type_Casing (Cmd) /= PP_Name_Casing (Cmd);
--         --  Following all the dependencies is fairly expensive, so we only do it
--         --  if necessary. It is necessary in order to get the casing right for
--         --  the name of a task body, which should be PP_Type_Casing if it's the
--         --  body of a task type, and PP_Name_Casing if it's the body of a
--         --  singleton task. Same issue for protected bodies. See Do_Def_Name in
--         --  ada_trees-formatting-tree_to_ada.adb.
--
--         Id : constant Unit_Id := Set_Get.Get_Unit_Id (CU);
--         use type System.WCh_Con.WC_Encoding_Method;

      --  Start of processing for Maybe_To_Ada

      begin
--         while Cache_Last < Id loop
--            Cache_Last := Cache_Last + 1;
--            Cache (Cache_Last) := null;
--         end loop;
--         pragma Assert (Cache (Id) /= Pending);
--         if Cache (Id) /= null then
--            pragma Assert (not To_Ada);
--            return;
--         end if;
--
--         Cache (Id) := Pending;

         if To_Ada then -- ??? or Skip_Gen then
--            Read_Ada_File (Src_Buf, File_Name,
--                           Opt.Wide_Character_Encoding_Method, Write_BOM,
--                           Expand_Tabs => True);
            Read_Ada_File (Src_Buf, File_Name,
                           System.WCh_Con.WCEM_Brackets, Write_BOM,
                           Expand_Tabs => True);
            --  Expand tabs unconditionally. This differs from the behavior of
            --  the old gnatpp, which has an option for that (but only for
            --  comments).
--            pragma Assert
--              (if Write_BOM then
--                 Opt.Wide_Character_Encoding_Method = System.WCh_Con.WCEM_UTF8);
--
--            if Skip_Gen then
--               Scanner.Get_Tokens
--                 (Src_Buf, Src_Tokens, LAL_UL.Ada_Version, Pp_Off_On_Delimiters,
--                  Gen_Regions => Src_Gen_Regions'Unchecked_Access);
--               Gen_Regions := Src_Gen_Regions'Unchecked_Access;
--            end if;
         end if;

--         declare
--            Tree : constant Ada_Tree :=
--              Compilation_Unit_To_Tree (CU, Gen_Regions);
--         begin
--            Cache (Id) := Tree;
--            Resolve_Symbols (Tree);
--
--            if Ada_Trees.Debug_Mode or else ASIS_UL.Debug.Debug_Flag_2 then
--               Ada_Trees.Self_Rep.Put_Ada_Tree (Tree);
--               Put ("\n");
--            end if;
--
--            if Do_Dependencies then
--               Walk_Direct_Dependencies (CU, Walk_Dependencies'Access);
--            end if;
--
            if To_Ada then
               Tree_To_Ada;
--                 (Tree, Src_Buf, Write_BOM, Cmd, Output_Name,
--                  Form_String, Do_Diff, Output_Written, Is_PP => True);
            end if;
--         end;
      end Maybe_To_Ada;

   --  Start of processing for Per_File_Action

   begin
      if Debug_Flag_V then
         Print (Unit);
         Put ("With trivia\n");
         PP_Trivia (Unit);
      end if;

--      case Output_Mode is
--         when Pipe | Replace_Modes | Default =>
--            pragma Assert (Res_File_Name = null);
--            pragma Assert (Out_Dir = null);
--         when Create_Modes =>
--            pragma Assert (Res_File_Name /= null);
--            pragma Assert (Out_Dir = null);
--         when Out_Directory =>
--            pragma Assert (Res_File_Name = null);
--            pragma Assert (Out_Dir /= null);
--
--            if Out_Dir.all =
--              Containing_Directory (Source_Name (SF))
--            then
--               Error ("--output-dir=" & Out_Dir.all);
--               Error (" contains input file " & Short_Source_Name (SF));
--               Error (" skipping " & Short_Source_Name (SF));
--               Error (" use -rnb to update source files in place");
--               return;
--            end if;
--      end case;
--
--      Set_Output_Encoding;
--
--      if Output_Mode = Replace and then
--         Is_Regular_File (Source_Name (SF) & NPP_Suffix)
--      then
--         Put (Standard_Error, "gnatpp: file ");
--         Put (Standard_Error,
--              To_Wide_String (Source_Name (SF) & NPP_Suffix));
--         Put (Standard_Error, " exists. Use '-rf' option to override");
--         New_Line (Standard_Error);
--         return;
--      end if;
--
--      if Output_Mode in Replace | Force_Replace then
--
--         if Verbose_Mode then
--            Put (Standard_Error, "gnatpp: creating the back-up copy ");
--            Put (Standard_Error, "of the original source ");
--            Put (Standard_Error, To_Wide_String (Source_Name (SF)));
--            New_Line (Standard_Error);
--         end if;
--
--         declare
--            Success : Boolean;
--         begin
--            Copy_File
--              (Name     => Source_Name (SF),
--               Pathname => Source_Name (SF) & NPP_Suffix,
--               Success  => Success,
--               Mode     => Overwrite);
--
--            if not Success then
--               Put (Standard_Error, "gnatpp: can not create ");
--               Put (Standard_Error, "the back-up copy for ");
--               Put (Standard_Error, To_Wide_String (Source_Name (SF)));
--               New_Line (Standard_Error);
--            end if;
--         end;
--
--      end if;

--      pragma Assert (Is_Empty (Symtab));
      Maybe_To_Ada (To_Ada => True);
--        (CU, Cmd, Output_Name, Form_String,
--         Do_Diff, Output_Written, To_Ada => True);
--      --  We have to flush the cache here, because Unit_Id's get reused between
--      --  runs of this.
--      Flush_Cache;
--      Clear (Symtab);
      Write_File_Name_File;
   end Per_File_Action;

   ---------------
   -- Tool_Help --
   ---------------

   procedure Tool_Help (Tool : Pp_Tool) is
      pragma Unreferenced (Tool);
      use LAL_UL.Formatted_Output;
   begin
      pragma Style_Checks ("M200"); -- Allow long lines

      Put ("usage: gnatpp [options] {filename} {-files filename} " &
            "[-cargs gcc_switches]\n");
      Put (" options:\n");
      Put (" --version - Display version and exit\n");
      Put (" --help    - Display usage and exit\n");
      Put ("\n");
      Put (" -Pproject     - Use project file project. Only one such switch can be used.\n");
      Put (" -U            - process all sources of the argument project\n");
      Put (" -U main       - process the closure of units rooted at unit main\n");
      Put (" -Xname=value  - specify an external reference for argument project file\n");
      Put (" -eL           - follow all symbolic links when processing project files\n");

      Put (" other options (in alphabetic order):\n");

      Put (" -A(0|1) - set alignment\n");
      Put ("   0 - set alignment OFF\n");
      Put ("   1 - set alignment ON (set as default)\n");

      Put (" -a(L|U|M) - set attribute casing\n");
      Put ("   L - lower case\n");
      Put ("   U - upper case\n");
      Put ("   M - mixed case (set as default)\n");

      Put (" --based-grouping=n  - underscores in based literals every n characters\n");

      Put (" -c(0|1|3|4|5) - comments layout\n");
      Put ("   0 - do not format comments\n");
      Put ("   1 - GNAT style comment line indentation (set as default)\n");
      Put ("   3 - GNAT style comment beginning\n");
      Put ("   4 - fill comment blocks\n");
      Put ("   5 - do not change comments with a special character " &
            "just after --\n");
      Put (" --comments-only - format just the comments\n");

      Put (" -clnnn - indentation level for continuation lines, " &
            "nnn from 1 .. 9\n");

      Put (" -D<file> - set <file> as the dictionary file defining casing " &
            "exceptions\n");
      Put (" -D-      - do not use RM-defined casing for predefined " &
            "names, use casing \n");
      Put ("            defined by -n parameter and dictionary file(s) " &
            "instead\n");

      Put (" --decimal-grouping=n  - underscores in decimal literals every n characters\n");

      Put (" -ff - put Form Feed after a pragma Page\n");
      Put (" -gnatec<path> - the same as GNAT -gnatec option\n");
      Put (" -innn - indentation level, nnn from 1 .. 9, " &
            "the default value is 3\n");

      Put (" -I<dir> - the same as gcc -I option\n");

      Put (" -I-     - the same as gcc -I- option\n");

      Put (" -k(L|U) - set keyword casing\n");
      Put ("   L - lower case (set as default)\n");
      Put ("   U - upper case\n");

      Put (" -Mnnn - set maximum line length, nnn from 32 .. 256, " &
            "the default value is 79\n");

      Put (" -n(D|U|L|M) - set name casing (for both defining and usage " &
            "occurrences)\n");
      Put ("   D - as declared (set as default)\n");
      Put ("   U - all in upper case\n");
      Put ("   L - all in lower case\n");
      Put ("   M - mixed\n");

      Put (" -ne(D|U|L|M) - set enumeration literal casing (for both defining and usage\n");
      Put ("                occurrences), parameters have the same meaning as for -n option\n");
      Put ("                if not set, -n is used to define enumeration literal casing\n");

      Put (" -nt(D|U|L|M) - set casing for names introduced by type and subtype\n");
      Put ("                declarations (both defining and usage occurrences), parameters\n");
      Put ("                have the same meaning as for -n option. If not set, -n is used\n");

      Put (" -nn(D|U|L|M) - set casing for names introduced by number declarations (both\n");
      Put ("                (defining and usage occurrences), parameters have the same\n");
      Put ("                meaning as for -n option. If not set, -n is used\n");

      Put (" -N - no tabulation in comments\n");

      Put (" -p(L|U|M) - set pragma casing\n");
      Put ("   L - lower case\n");
      Put ("   U - upper case\n");
      Put ("   M - mixed case (set as default)\n");

      Put (" --pp-off=xxx - Use ""--xxx"" as the comment string to disable\n");
      Put ("                pretty printing instead of the default " &
              """--!pp off""\n");
      Put (" --pp-on=xxx - Use ""--xxx"" as the comment string to reenable\n");
      Put ("                pretty printing instead of the default " &
              """--!pp on""\n");

      Put (" --RTS=<dir> - the same as gcc --RTS option\n");

      Put (" -q  - quiet mode\n");

      Put (" --no-separate-is        - try not to place 'IS' on a separate " &
            " line in\n");
      Put ("                           a subprogram body\n");
      Put (" --separate-loop-then    - use a separate line for LOOP and " &
            "THEN keywords\n");

      Put (" --no-separate-loop-then - do not use a separate line for LOOP " &
            "and THEN\n");
      Put ("                           keywords, uncompatible with " &
            "--separate-loop-then\n");

      Put (" --use-on-new-line       - use separate lines for USE clauses \n");
      Put ("                           in a context clause\n");

      Put (" --insert-blank-lines    - insert blank lines where appropriate\n");

      Put (" --preserve-blank-lines  - preserve blank lines in the input\n");

      Put (" --split-line-before-op  - operator on next line\n");

      Put (" --RM-style-spacing      - no extra space before " &
            "'(' and ':'\n");

      Put (" --par_threshold=nnn     - if the number of parameter specifications is greater\n");
      Put ("                           than nnn, each specification starts from a new line\n");

      Put (" --call_threshold=nnn    - if the number of parameter associations in a call is\n");
      Put ("                           greater than nnn and there is at least one named\n");
      Put ("                           association, each association starts from a new line\n");

      Put (" --incremental -- incremental processing on a per-file basis\n");
      Put (" -jn - n is the maximal number of processes to carry out\n");
      Put (" -t  - display execution time\n");

      Put (" -v  - verbose mode\n");

      Put (" -dd - progress indicator verbose mode\n");
      Put ("\n");

      Put ("Output file control:\n");
      Put (" -pipe - send the output into Stdout\n");
      Put (" -o output_file - write the output into output_file. Give up " &
            "if output_file\n");
      Put ("                  already exists\n");
      Put (" -of output_file - write the output into output_file, " &
            "overriding the existing \n");
      Put ("                   file\n");
      Put (" --output-dir=dir -- create output files in dir\n");
      Put (" -r   - replace the argument source with the pretty-printed" &
            " source and copy the\n");
      Put ("        argument source into filename.npp" &
            ". Give up if filename.npp\n");
      Put ("        already exists\n");
      Put (" -rf  - replace the argument source with the pretty-printed " &
            "source and copy the\n");
      Put ("        argument source into filename.npp" &
            ", overriding the existing file\n");

      Put (" -rnb - replace the argument source with the pretty-printed " &
            "source and do not\n");
      Put ("        create the back-up copy of the argument source\n");
      Put ("\n");

      Put (" filename - the name of the Ada source file to be reformatted. \n");
      Put ("            Wildcards are allowed\n");
      Put (" -files=filename - the name of a text file containing a list\n");
      Put ("                   of Ada source files to reformat\n");
      Put (" --eol=text_format - sets the format of the gnatpp output " &
        "file(s),\n");
      Put ("                    can not be used together with -pipe option\n");
      Put ("       text_format can be - 'unix' or 'lf'   - lines end with " &
        "LF character\n");
      Put ("                          - 'dos'  or 'crlf' - lines end with " &
        "CRLF characters\n");

      Put (" -W(h|u|s|e|8|b) - sets the wide character encoding of the " &
        "result file\n");
      Put ("    h - Hex ESC encoding\n");
      Put ("    u - Upper half encoding\n");
      Put ("    s - Shift-JIS encoding\n");
      Put ("    e - EUC Encoding\n");
      Put ("    8 - UTF-8 encoding\n");
      Put ("    b - Brackets encoding (this is the default)\n");
      Put ("\n");

      Put (" gcc_switches - switches to be passed to gcc called by \1\n",
            Tool_Names.Tool_Name);

      Put ("\n\nReport bugs to report@adacore.com\n");

      pragma Style_Checks ("M79");
   end Tool_Help;

   procedure Dump
     (Tool : in out Pp_Tool;
      Message : String := "")
   is
      pragma Unreferenced (Tool);
      use LAL_UL.Formatted_Output;
   begin
      if Debug_Flag_V then
         Put ("\1\n", Message);
      end if;
   end Dump;

   procedure Put_Ada_Templates is
      use Formatted_Output, Ada.Strings.Fixed;
   begin
      Put ("--  Templates:\n");

      for Kind in Ada_Tree_Kind loop
         if Template_Table (Kind) /= null then
            declare
               T : constant String :=
                 To_UTF8 (W_Str (Template_Table (Kind).all));

            begin
               Put
                 ("--  \1 => \2",
                  Capitalize (Kind'Img),
                  (if Template_Table (Kind) = null then "null"
                   else """" & T & """"));
               if Count (T, "[") /= Count (T, "]") then
                  Put ("    MISMATCHED [...]");
                  raise Program_Error;
               end if;
               if Count (T, "{") /= Count (T, "}") then
                  Put ("    MISMATCHED {...}");
                  raise Program_Error;
               end if;
               if Count (T, "(") /= Count (T, ")") then
                  Put ("    MISMATCHED (...)");
                  raise Program_Error;
               end if;
               Put ("\n");
            end;
         end if;
      end loop;
      Put ("--  End templates.\n");
   end Put_Ada_Templates;

end Pp.Actions;
