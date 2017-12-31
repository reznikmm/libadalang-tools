-- C24106A.ADA

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
--     CHECK THAT UNDERSCORE CHARACTERS ARE PERMITTED IN ANY PART OF
--     A NON-BASED DECIMAL LITERAL.

-- HISTORY:
--     DHH 01/19/88 CREATED ORIGINAL TEST

with Report; use Report;

procedure C24106a is

begin
   Test
     ("C24106A",
      "CHECK THAT UNDERSCORE CHARACTERS " & "ARE PERMITTED IN ANY PART OF " &
      "A NON-BASED DECIMAL LITERAL");

   if 1.2_3_4_5_6 /= 1.234_56 then
      Failed
        ("UNDERSCORES NOT PERMITTED IN FRACTIONAL PART " &
         "OF A NON_BASED LITERAL");
   end if;
   if 1_2_3_4_5.6 /= 12_345.6 then
      Failed
        ("UNDERSCORES NOT PERMITTED IN INTEGRAL PART " &
         "OF A NON_BASED LITERAL");
   end if;
   if 0.12E1_2 /= 0.12E12 then
      Failed
        ("UNDERSCORES NOT PERMITTED IN EXPONENT PART " &
         "OF A NON_BASED LITERAL");
   end if;
   if 1_2_3_4_5 /= 12_345 then
      Failed
        ("UNDERSCORES NOT PERMITTED IN INTEGRAL PART " &
         "OF A NON_BASED LITERAL INTEGER");
   end if;
   if 0E1_0 /= 0 then
      Failed
        ("UNDERSCORES NOT PERMITTED IN EXPONENT PART " &
         "OF A NON_BASED LITERAL INTEGER");
   end if;

   Result;
end C24106a;
