-- CE2201B.ADA

--                             Grant of Unlimited Rights
--
--     Under contracts F33600-87-D-0337, F33600-84-D-0280, MDA903-79-C-0687,
--     F08630-91-C-0015, and DCA100-97-D-0025, the U.S. Government obtained
--     unlimited rights in the software and documentation contained herein.
--     Unlimited rights are defined in DFAR 252.227-7013(a)(19).  By making
--     this public release, the Government intends to confer upon all
--     recipients unlimited rights  equal to those held by the Government.
--     These rights include rights to use, duplicate, release or disclose the
--     released technical data and computer software in whole or in part, in
--     any manner and for any purpose whatsoever, and to have or permit others
--     to do so.
--
--                                    DISCLAIMER
--
--     ALL MATERIALS OR INFORMATION HEREIN RELEASED, MADE AVAILABLE OR
--     DISCLOSED ARE AS IS.  THE GOVERNMENT MAKES NO EXPRESS OR IMPLIED
--     WARRANTY AS TO ANY MATTER WHATSOEVER, INCLUDING THE CONDITIONS OF THE
--     SOFTWARE, DOCUMENTATION OR OTHER INFORMATION RELEASED, MADE AVAILABLE
--     OR DISCLOSED, OR THE OWNERSHIP, MERCHANTABILITY, OR FITNESS FOR A
--     PARTICULAR PURPOSE OF SAID MATERIAL.
--*
-- OBJECTIVE:
--     CHECK THAT READ, WRITE, AND END_OF_FILE ARE SUPPORTED FOR
--     SEQUENTIAL FILES WITH ELEMENT_TYPE CONSTRAINED ARRAY.

-- APPLICABILITY CRITERIA:
--     THIS TEST IS APPLICABLE ONLY TO IMPLEMENTATIONS WHICH SUPPORT
--     SEQUENTIAL FILES WITH ELEMENT_TYPE CONSTRAINED ARRAY.

-- HISTORY:
--     ABW 08/17/82
--     SPS 09/15/82
--     SPS 11/09/82
--     JBG 05/02/83
--     EG  05/08/85
--     TBN 11/04/86  REVISED TEST TO OUTPUT A NOT_APPLICABLE
--                   RESULT WHEN FILES ARE NOT SUPPORTED.
--     JLH 07/28/87  REMOVED THE DEPENDENCE OF RESET BEING SUPPORTED
--                   AND CREATED EXTERNAL FILES RATHER THAN TEMPORARY
--                   FILES.

with Report; use Report;
with Sequential_Io;

procedure Ce2201b is

begin

   Test
     ("CE2201B",
      "CHECK THAT READ, WRITE, AND " & "END_OF_FILE ARE SUPPORTED FOR " &
      "SEQUENTIAL FILES - CONSTRAINED ARRAY");

   declare
      type Arr_Cn is array (1 .. 5) of Boolean;
      package Seq_Arr_Cn is new Sequential_Io (Arr_Cn);
      use Seq_Arr_Cn;
      File_Arr_Cn : File_Type;
      Incomplete : exception;
      Arr1      : Arr_Cn := (True, True, False, True, True);
      Item_Arr1 : Arr_Cn;
   begin
      begin
         Create (File_Arr_Cn, Out_File, Legal_File_Name);
      exception
         when Use_Error | Name_Error =>
            Not_Applicable
              ("CREATE OF SEQUENTIAL FILE WITH " &
               "MODE OUT_FILE NOT SUPPORTED");
            raise Incomplete;
      end;

      Write (File_Arr_Cn, Arr1);
      Close (File_Arr_Cn);

      begin
         Open (File_Arr_Cn, In_File, Legal_File_Name);
      exception
         when Use_Error =>
            Not_Applicable
              ("OPEN OF SEQUENTIAL FILE WITH " & "MODE IN_FILE NOT SUPPORTED");
            raise Incomplete;
      end;

      if End_Of_File (File_Arr_Cn) then
         Failed ("WRONG END_OF_FILE VALUE FOR " & "CONSTRAINED ARRAY");
      end if;

      Read (File_Arr_Cn, Item_Arr1);

      if Item_Arr1 /= Arr1 then
         Failed ("READ WRONG VALUE - CONSTRAINED ARRAY");
      end if;

      if not End_Of_File (File_Arr_Cn) then
         Failed ("END OF FILE NOT TRUE - CONSTRAINED ARRAY");
      end if;

      begin
         Delete (File_Arr_Cn);
      exception
         when Use_Error =>
            null;
      end;

   exception
      when Incomplete =>
         null;
   end;

   Result;

end Ce2201b;
