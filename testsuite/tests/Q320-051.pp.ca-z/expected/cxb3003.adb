-- CXB3003.A
--
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
--
-- OBJECTIVE:
--      Check that the specifications of the package Interfaces.C.Pointers
--      are available for use.
--
-- TEST DESCRIPTION:
--      This test verifies that the types and subprograms specified for the
--      interface are present
--
-- APPLICABILITY CRITERIA:
--      If an implementation provides package Interfaces.C.Pointers, this
--      test must compile, execute, and report "PASSED".
--
--
-- CHANGE HISTORY:
--      06 Dec 94   SAIC    ACVC 2.0
--      28 Feb 96   SAIC    Added applicability criteria.
--
--!

with Report;
with Interfaces.C.Pointers;                                   -- N/A => ERROR

procedure Cxb3003 is
   package C renames Interfaces.C;

   package Test_Ptrs is new C.Pointers (Index => C.Size_T, Element => C.Char,
      Element_Array => C.Char_Array, Default_Terminator => C.Nul);

begin

   Report.Test ("CXB3003", "Check the specification of Interfaces.C.Pointers");

   declare  -- encapsulate the test

      Tc_Int : Integer := 1;

      --  Note: In all of the following the Pointers spec. being tested is
      --  shown in comments
      --
      --    type Pointer is access all Element;
      subtype Tst_Pointer_Type is Test_Ptrs.Pointer;

      Tst_Element   : C.Char           := C.Char'First;
      Tst_Pointer   : Tst_Pointer_Type := null;
      Tst_Pointer_2 : Tst_Pointer_Type := null;
      Tst_Array     : C.Char_Array (1 .. 5);
      Tst_Index     : C.Ptrdiff_T      := C.Ptrdiff_T'First;

   begin    -- encapsulation

      -- Arrange that the calls to the subprograms are compiled but not
      -- executed
      --
      if not Report.Equal (Tc_Int, Tc_Int) then

         --    function Value (Ref        : in Pointer;
         --                    Terminator : in Element := Default_Terminator)
         --      return Element_Array;

         Tst_Array := Test_Ptrs.Value (Tst_Pointer);  -- default
         Tst_Array := Test_Ptrs.Value (Tst_Pointer, Tst_Element);

         --    function Value (Ref    : in Pointer; Length : in ptrdiff_t)
         --      return Element_Array;

         Tst_Array := Test_Ptrs.Value (Tst_Pointer, Tst_Index);

         --
         --    --  C-style Pointer arithmetic
         --
         --    function "+" (Left : in Pointer;   Right : in ptrdiff_t)
         --                                                 return Pointer;
         Tst_Pointer := Test_Ptrs."+" (Tst_Pointer, Tst_Index);

         --    function "+" (Left : in Ptrdiff_T; Right : in Pointer)
         --                                                 return Pointer;
         Tst_Pointer := Test_Ptrs."+" (Tst_Index, Tst_Pointer);

         --    function "-" (Left : in Pointer;   Right : in ptrdiff_t)
         --                                                 return Pointer;
         Tst_Pointer := Test_Ptrs."-" (Tst_Pointer, Tst_Index);

         --    function "-" (Left : in Pointer;   Right : in Pointer)
         --                                                 return ptrdiff_t;
         Tst_Index := Test_Ptrs."-" (Tst_Pointer, Tst_Pointer);

         --    procedure Increment (Ref : in out Pointer);
         Test_Ptrs.Increment (Tst_Pointer);

         --    procedure Decrement (Ref : in out Pointer);
         Test_Ptrs.Decrement (Tst_Pointer);

         --    function Virtual_Length
         --                 ( Ref        : in Pointer;
         --                   Terminator : in Element := Default_Terminator)
         --      return ptrdiff_t;
         Tst_Index := Test_Ptrs.Virtual_Length (Tst_Pointer);
         Tst_Index := Test_Ptrs.Virtual_Length (Tst_Pointer, Tst_Element);

         --    procedure Copy_Terminated_Array
         --      (Source     : in Pointer;
         --       Target     : in Pointer;
         --       Limit      : in ptrdiff_t := ptrdiff_t'Last;
         --       Terminator : in Element := Default_Terminator);

         Test_Ptrs.Copy_Terminated_Array (Tst_Pointer, Tst_Pointer_2);

         Test_Ptrs.Copy_Terminated_Array
           (Tst_Pointer, Tst_Pointer_2, Tst_Index);

         Test_Ptrs.Copy_Terminated_Array
           (Tst_Pointer, Tst_Pointer_2, Tst_Index, Tst_Element);

         --    procedure Copy_Array
         --      (Source  : in Pointer;
         --       Target  : in Pointer;
         --       Length  : in ptrdiff_t);

         Test_Ptrs.Copy_Array (Tst_Pointer, Tst_Pointer_2, Tst_Index);

         --    This is out of LRM order to avoid complaints from compilers
         --    about inaccessible code
         --       Pointer_Error : exception;

         raise Test_Ptrs.Pointer_Error;

      end if;

   end;     -- encapsulation

   Report.Result;

end Cxb3003;
