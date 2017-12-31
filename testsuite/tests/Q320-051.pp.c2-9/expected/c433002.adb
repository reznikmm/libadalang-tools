-- C433002.A

--                             Grant of Unlimited Rights
--
--     The Ada Conformity Assessment Authority (ACAA) holds unlimited
--     rights in the software and documentation contained herein. Unlimited
--     rights are the same as those granted by the U.S. Government for older
--     parts of the Ada Conformity Assessment Test Suite, and are defined
--     in DFAR 252.227-7013(a)(19). By making this public release, the ACAA
--     intends to confer upon all recipients unlimited rights equal to those
--     held by the ACAA. These rights include rights to use, duplicate,
--     release or disclose the released technical data and computer software
--     in whole or in part, in any manner and for any purpose whatsoever, and
--     to have or permit others to do so.
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
-- OBJECTIVE
--     Check that index choices are within the applicable index
--     constraint for array aggregates with others choices. (Case 2: <>
--     components.)
--
-- TEST DESCRIPTION
--     In this test, we declare several unconstrained array types, and
--     several dynamic subtypes. We then test a variety of cases of using
--     appropriate aggregates. Some cases expect to raise Constraint_Error.
--
--     The rule in question was modified by AI05-0037-1 to include components
--     specified with <>.
--
-- HISTORY:
--      21 NOV 2014   RLB   Created from C433001.

with Report;
procedure C433002 is

   type Color_Type is (Red, Orange, Yellow, Green, Blue, Indigo, Violet);

   type Default_To_Zero is range -10_000 .. 10_000 with
      Default_Value => 0;

   function Ident_Int (Val : in Default_To_Zero) return Default_To_Zero is
     (Default_To_Zero (Report.Ident_Int (Integer (Val))));

   type Array_1 is array (Positive range <>) of Default_To_Zero;

   subtype Sub_1_1 is Array_1 (Report.Ident_Int (1) .. Report.Ident_Int (3));
   subtype Sub_1_2 is Array_1 (Report.Ident_Int (3) .. Report.Ident_Int (5));
   subtype Sub_1_3 is Array_1 (Report.Ident_Int (5) .. Report.Ident_Int (9));

   type Array_2 is array (Color_Type range <>) of Default_To_Zero;

   subtype Sub_2_1 is
     Array_2
       (Color_Type'Val (Report.Ident_Int (0)) ..
            Color_Type'Val (Report.Ident_Int (2)));
   -- Red .. Yellow
   subtype Sub_2_2 is
     Array_2
       (Color_Type'Val (Report.Ident_Int (3)) ..
            Color_Type'Val (Report.Ident_Int (6)));
   -- Green .. Violet
   type Array_3 is
     array (Color_Type range <>, Positive range <>) of Default_To_Zero;

   subtype Sub_3_1 is
     Array_3
       (Color_Type'Val (Report.Ident_Int (0)) ..
            Color_Type'Val (Report.Ident_Int (2)),
        Report.Ident_Int (3) .. Report.Ident_Int (5));
   -- Red .. Yellow, 3 .. 5
   subtype Sub_3_2 is
     Array_3
       (Color_Type'Val (Report.Ident_Int (1)) ..
            Color_Type'Val (Report.Ident_Int (3)),
        Report.Ident_Int (6) .. Report.Ident_Int (8));
   -- Orange .. Green, 6 .. 8

   procedure Check_1 (Obj : Array_1; Low, High : Integer;
      First_Component, Second_Component, Last_Component : Default_To_Zero;
      Test_Case                                         : Character)
   is
   begin
      if Obj'First /= Low then
         Report.Failed ("Low bound incorrect (" & Test_Case & ")");
      end if;
      if Obj'Last /= High then
         Report.Failed ("High bound incorrect (" & Test_Case & ")");
      end if;
      if Obj (Low) /= First_Component then
         Report.Failed ("First Component incorrect (" & Test_Case & ")");
      end if;
      if Obj (Low + 1) /= Second_Component then
         Report.Failed ("Second Component incorrect (" & Test_Case & ")");
      end if;
      if Obj (High) /= Last_Component then
         Report.Failed ("Last Component incorrect (" & Test_Case & ")");
      end if;
   end Check_1;

   procedure Check_2 (Obj : Array_2; Low, High : Color_Type;
      First_Component, Second_Component, Last_Component : Default_To_Zero;
      Test_Case                                         : Character)
   is
   begin
      if Obj'First /= Low then
         Report.Failed ("Low bound incorrect (" & Test_Case & ")");
      end if;
      if Obj'Last /= High then
         Report.Failed ("High bound incorrect (" & Test_Case & ")");
      end if;
      if Obj (Low) /= First_Component then
         Report.Failed ("First Component incorrect (" & Test_Case & ")");
      end if;
      if Obj (Color_Type'Succ (Low)) /= Second_Component then
         Report.Failed ("Second Component incorrect (" & Test_Case & ")");
      end if;
      if Obj (High) /= Last_Component then
         Report.Failed ("Last Component incorrect (" & Test_Case & ")");
      end if;
   end Check_2;

   procedure Check_3 (Test_Obj, Check_Obj : Array_3;
      Low_1, High_1 : Color_Type; Low_2, High_2 : Integer;
      Test_Case                           : Character)
   is
   begin
      if Test_Obj'First (1) /= Low_1 then
         Report.Failed
           ("Low bound for dimension 1 incorrect (" & Test_Case & ")");
      end if;
      if Test_Obj'Last (1) /= High_1 then
         Report.Failed
           ("High bound for dimension 1 incorrect (" & Test_Case & ")");
      end if;
      if Test_Obj'First (2) /= Low_2 then
         Report.Failed
           ("Low bound for dimension 2 incorrect (" & Test_Case & ")");
      end if;
      if Test_Obj'Last (2) /= High_2 then
         Report.Failed
           ("High bound for dimension 2 incorrect (" & Test_Case & ")");
      end if;
      if Test_Obj /= Check_Obj then
         Report.Failed ("Components incorrect (" & Test_Case & ")");
      end if;
   end Check_3;

   procedure Subtest_Check_1 (Obj                       : Sub_1_3;
      First_Component, Second_Component, Last_Component : Default_To_Zero;
      Test_Case                                         : Character)
   is
   begin
      Check_1
        (Obj, 5, 9, First_Component, Second_Component, Last_Component,
         Test_Case);
   end Subtest_Check_1;

   procedure Subtest_Check_2 (Obj                       : Sub_2_2;
      First_Component, Second_Component, Last_Component : Default_To_Zero;
      Test_Case                                         : Character)
   is
   begin
      Check_2
        (Obj, Green, Violet, First_Component, Second_Component, Last_Component,
         Test_Case);
   end Subtest_Check_2;

   procedure Subtest_Check_3 (Obj : Sub_3_2; Test_Case : Character) is
   begin
      Check_3 (Obj, Obj, Orange, Green, 6, 8, Test_Case);
   end Subtest_Check_3;

begin

   Report.Test
     ("C433002",
      "Check check index choices are within the applicable index " &
      "constraint for array aggregates with others choices where " &
      "the components are <>");

   -- Check with a qualified expression:
   Check_1
     (Sub_1_1'(2, 3, others => <>), Low => 1, High => 3, First_Component => 2,
      Second_Component => 3, Last_Component => 0, Test_Case => 'A');

   -- Check that the others clause does not need to represent any components:
   Check_1
     (Sub_1_2'(5, 6, 8, others => <>), Low => 3, High => 5,
      First_Component => 5, Second_Component => 6, Last_Component => 8,
      Test_Case       => 'D');

   -- Check named choices are allowed:
   Check_1
     (Sub_1_1'(2 => <>, others => 8), Low => 1, High => 3,
      First_Component => 8, Second_Component => 0, Last_Component => 8,
      Test_Case       => 'E');

   -- Check named choices and formal parameters:
   Subtest_Check_1
     ((6 => <>, 8 => <>, others => 1), First_Component => 1,
      Second_Component => 0, Last_Component => 1, Test_Case => 'F');

   Subtest_Check_3
     ((Yellow => (7 => <>, others => 10), others => (1, 2, 3)),
      Test_Case => 'H');

   -- Check object declarations and assignment:
   declare
      Var : Sub_1_2 := (4, 36, others => <>);
   begin
      Check_1
        (Var, Low         => 3, High => 5, First_Component => 4,
         Second_Component => 36, Last_Component => 0, Test_Case => 'I');
      Var := (5 => <>, others => Ident_Int (1_522));
      Check_1
        (Var, Low         => 3, High => 5, First_Component => 1_522,
         Second_Component => 1_522, Last_Component => 0, Test_Case => 'J');
   end;

   -- Check positional aggregates that are too long:
   begin
      Subtest_Check_2
        ((Ident_Int (88), 89, 90, 91, 92, others => <>), First_Component => 88,
         Second_Component => 89, Last_Component => 91, Test_Case => 'K');
      Report.Failed
        ("Constraint_Error not raised by positional " &
         "aggregate with too many choices (K)");
   exception
      when Constraint_Error =>
         null; -- Expected exception.
   end;

   begin
      Subtest_Check_3
        (((0, others => <>), (2, 3, others => <>), (5, 6, 8, others => 10),
          (1, 4, 7), others => (1, 2, 3)),
         Test_Case => 'L');
      Report.Failed
        ("Constraint_Error not raised by positional " &
         "aggregate with too many choices (L)");
   exception
      when Constraint_Error =>
         null; -- Expected exception.
   end;

   -- Check named aggregates with choices in the index subtype but not in the
   -- applicable index constraint:

   begin
      Subtest_Check_1
        (
         (5      => Ident_Int (88),
          8      => <>,
          10     => <>, -- 10 not in applicable index constraint
          others => <>),
         First_Component => 88, Second_Component => 0, Last_Component => 0,
         Test_Case       => 'M');
      Report.Failed
        ("Constraint_Error not raised by aggregate choice " &
         "index outside of applicable index constraint (M)");
   exception
      when Constraint_Error =>
         null; -- Expected exception.
   end;

   begin
      Subtest_Check_2
        (
         (Yellow => <>, -- Yellow not in applicable index constraint.
          Blue   => <>, others => 77), First_Component => 77,
         Second_Component => 0, Last_Component => 77, Test_Case => 'N');
      Report.Failed
        ("Constraint_Error not raised by aggregate choice " &
         "index outside of applicable index constraint (N)");
   exception
      when Constraint_Error =>
         null; -- Expected exception.
   end;

   begin
      Subtest_Check_3
        (
         (Orange => (0, others => <>),
          Blue   => (2, 3, others => <>), -- Blue not in applicable index cons.
          others => (1, 2, 3)),
         Test_Case => 'P');
      Report.Failed
        ("Constraint_Error not raised by aggregate choice " &
         "index outside of applicable index constraint (P)");
   exception
      when Constraint_Error =>
         null; -- Expected exception.
   end;

   begin
      Subtest_Check_3
        ((Orange => (6 => 0, others => Ident_Int (10)),
          Green  => (8 => <>, 4 => <>, others => 7),
      -- 4 not in applicable index cons.
          others => (1, 2, 3, others => Ident_Int (10))),
         Test_Case => 'Q');
      Report.Failed
        ("Constraint_Error not raised by aggregate choice " &
         "index outside of applicable index constraint (Q)");
   exception
      when Constraint_Error =>
         null; -- Expected exception.
   end;

   Report.Result;

end C433002;
