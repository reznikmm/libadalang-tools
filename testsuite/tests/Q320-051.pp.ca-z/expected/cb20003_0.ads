-- CB20003.A
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
--      Check that exceptions can be raised, reraised, and handled in an
--      accessed subprogram.
--
--
-- TEST DESCRIPTION:
--      Declare a record type, with one component being an access to
--      subprogram type.  Various subprograms are defined to fit the profile
--      of this access type, such that the record component can refer to
--      any of the subprograms.
--
--      Each of the subprograms raises a different exception, based on the
--      value of an input parameter.  Exceptions are 1) raised, handled with
--      an others handler, reraised and propagated to main to be handled in
--      a specific handler; 2) raised, handled in a specific handler, reraised
--      and propagated to the main to be handled in an others handler there,
--      and 3) raised and propagated directly to the caller by the subprogram.
--
--      Boolean variables are set throughout the test to ensure that correct
--      exception processing has occurred, and these variables are verified at
--      the conclusion of the test.
--
--
-- CHANGE HISTORY:
--      06 Dec 94   SAIC    ACVC 2.0
--
--!

package Cb20003_0 is                          -- package Push_Buttons

   Non_Default_Priority, Non_Alert_Priority,
   Non_Emergency_Priority : exception;

   Handled_With_Others, Reraised_In_Subprogram, Handled_In_Caller : Boolean :=
     False;

   subtype Priority_Type is Integer range 1 .. 10;

   Default_Priority   : Priority_Type := 1;
   Alert_Priority     : Priority_Type := 3;
   Emergency_Priority : Priority_Type := 5;

   type Button is tagged private;                  -- Private tagged type.

   type Button_Response_Ptr is access procedure (P : in     Priority_Type;
      B                                            : in out Button);

   -- Procedures accessible with Button_Response_Ptr type.

   procedure Default_Response (P : in Priority_Type; B : in out Button);

   procedure Alert_Response (P : in Priority_Type; B : in out Button);

   procedure Emergency_Response (P : in Priority_Type; B : in out Button);

   procedure Push (B : in out Button; P : in Priority_Type);

   procedure Set_Response (B : in out Button; R : in Button_Response_Ptr);

private

   type Button is tagged record
      Priority : Priority_Type       := Default_Priority;
      Response : Button_Response_Ptr := Default_Response'Access;
   end record;

end Cb20003_0;                                -- package Push_Buttons
