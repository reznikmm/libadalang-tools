-- CXACA01.A
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
--      Check that the default attributes 'Write and 'Read work properly when
--      used with objects of a variety of types, including records with
--      default discriminants, records without default discriminants, but
--      which have the discriminant described in a representation clause for
--      the type, and arrays.
--
-- TEST DESCRIPTION:
--      This test simulates a basic sales record system, using Stream_IO to
--      allow the storage of heterogeneous data in a single stream file.
--
--      Four types of data are written to the stream file for each product.
--      First, the "header" information on the product is written.
--      This is an object of a discriminated (with default) record
--      type.  This is followed by an integer object containing a count of
--      the number of sales data records to follow.  The corresponding number
--      of sales records follow in the stream.  These are of a record type
--      with a discriminant without a default, but where the discriminant is
--      included in the representation clause for the type. Finally, an
--      array object with statistical sales information for the product is
--      written to the stream.
--
--      Objects of both record types specified below (discriminated records
--      with defaults, and discriminated records w/o defaults that have the
--      discriminant included in a representation clause for the type) should
--      have their discriminants included in the stream when using 'Write.
--      Likewise, discriminants should be extracted from the stream when
--      using 'Read.
--
-- APPLICABILITY CRITERIA:
--      Applicable to all implementations that support external
--      Stream_IO files.
--
--
-- CHANGE HISTORY:
--      06 Dec 94   SAIC    ACVC 2.0
--
--!

with Fxaca00;
with Ada.Streams.Stream_Io;
with Report;

procedure Cxaca01 is

begin

   Report.Test
     ("CXACA01",
      "Check that 'Write and 'Read work properly " &
      "when used with complex data types");

   Test_For_Stream_Io_Support :
   declare

      Info_File    : Ada.Streams.Stream_Io.File_Type;
      Info_Stream  : Ada.Streams.Stream_Io.Stream_Access;
      The_Filename : constant String := Report.Legal_File_Name;

   begin

      -- If an implementation does not support Stream_IO in a particular
      -- environment, the exception Use_Error or Name_Error will be raised on
      -- calls to various Stream_IO operations. This block statement encloses a
      -- call to Create, which should produce an exception in a non-supportive
      -- environment. These exceptions will be handled to produce a
      -- Not_Applicable result.

      Ada.Streams.Stream_Io.Create
        (Info_File, Ada.Streams.Stream_Io.Out_File, The_Filename);

      Operational_Test_Block :
      declare

      begin

         Info_Stream := Ada.Streams.Stream_Io.Stream (Info_File);

         -- Write all of the product information (record, integer, and array
         -- objects) defined in package FXACA00 into the stream.

         Store_Data_Block :
         begin

            -- Write information about first product to the stream.
            Fxaca00.Product_Type'Write (Info_Stream, Fxaca00.Product_01);
            Integer'Write (Info_Stream, Fxaca00.Sale_Count_01);
            Fxaca00.Sales_Record_Type'Write (Info_Stream, Fxaca00.Sale_Rec_01);
            Fxaca00.Sales_Record_Type'Write (Info_Stream, Fxaca00.Sale_Rec_02);
            Fxaca00.Sales_Statistics_Type'Write (Info_Stream,
               Fxaca00.Product_01_Stats);

            -- Write information about second product to the stream. Note: No
            -- Sales_Record_Type objects.
            Fxaca00.Product_Type'Write (Info_Stream, Fxaca00.Product_02);
            Integer'Write (Info_Stream, Fxaca00.Sale_Count_02);
            Fxaca00.Sales_Statistics_Type'Write (Info_Stream,
               Fxaca00.Product_02_Stats);

            -- Write information about third product to the stream.
            Fxaca00.Product_Type'Write (Info_Stream, Fxaca00.Product_03);
            Integer'Write (Info_Stream, Fxaca00.Sale_Count_03);
            Fxaca00.Sales_Record_Type'Write (Info_Stream, Fxaca00.Sale_Rec_03);
            Fxaca00.Sales_Record_Type'Write (Info_Stream, Fxaca00.Sale_Rec_04);
            Fxaca00.Sales_Record_Type'Write (Info_Stream, Fxaca00.Sale_Rec_05);
            Fxaca00.Sales_Statistics_Type'Write (Info_Stream,
               Fxaca00.Product_03_Stats);

         end Store_Data_Block;

         Verify_Data_Block :
         declare

            use Fxaca00;   -- Used within this block only.

            type Domestic_Rec_Array_Type is
              array (Positive range <>) of Sales_Record_Type (Domestic);

            type Foreign_Rec_Array_Type is
              array (Positive range <>) of Sales_Record_Type (Foreign);

            Tc_Rec1 : Domestic_Rec_Array_Type (1 .. 2);
            Tc_Rec3 : Foreign_Rec_Array_Type (1 .. 3);

            Tc_Product1              : Product_Type;
            Tc_Product2, Tc_Product3 : Product_Type (Foreign);

            Tc_Count1, Tc_Count2, Tc_Count3 : Integer :=
              -10;  -- Initialized to dummy value.

            Tc_Stat1, Tc_Stat2, Tc_Stat3 : Sales_Statistics_Type :=
              (others => 500);

         begin

            Ada.Streams.Stream_Io.Reset
              (Info_File, Ada.Streams.Stream_Io.In_File);

            -- Read all of the data that is contained in the stream. Compare
            -- all data with the original data in package FXACA00 that was
            -- written to the stream. The calls to the read attribute are in
            -- anticipated order, based on the order of data written to the
            -- stream. Possible errors, such as data placement, overwriting,
            -- etc., will be manifest as exceptions raised by the attribute
            -- during an unsuccessful read attempt.

            -- Extract data on first product.
            Product_Type'Read (Info_Stream, Tc_Product1);
            Integer'Read (Info_Stream, Tc_Count1);

            -- Two "domestic" variant sales records will be read from the
            -- stream.
            for I in 1 .. Tc_Count1 loop
               Sales_Record_Type'Read (Info_Stream, Tc_Rec1 (I));
            end loop;

            Sales_Statistics_Type'Read (Info_Stream, Tc_Stat1);

            -- Extract data on second product.
            Product_Type'Read (Info_Stream, Tc_Product2);
            Integer'Read (Info_Stream, Tc_Count2);
            Sales_Statistics_Type'Read (Info_Stream, Tc_Stat2);

            -- Extract data on third product.
            Product_Type'Read (Info_Stream, Tc_Product3);
            Integer'Read (Info_Stream, Tc_Count3);

            -- Three "foreign" variant sales records will be read from the
            -- stream.
            for I in 1 .. Tc_Count3 loop
               Sales_Record_Type'Read (Info_Stream, Tc_Rec3 (I));
            end loop;

            Sales_Statistics_Type'Read (Info_Stream, Tc_Stat3);

            -- After all the data has been correctly extracted, the file should
            -- be empty.

            if not Ada.Streams.Stream_Io.End_Of_File (Info_File) then
               Report.Failed ("Stream file not empty");
            end if;

            -- Verify that the data values read from the stream are the same as
            -- those written to the stream.

            -- Verify the information of the first product.
            if
              ((Product_01 /= Tc_Product1)
               or else (Product_01.Manufacture /= Tc_Product1.Manufacture)
               or else (Sale_Count_01 /= Tc_Count1)
               or else (Sale_Rec_01 /= Tc_Rec1 (1))
               or else (Sale_Rec_01.Buyer /= Tc_Rec1 (1).Buyer)
               or else (Sale_Rec_02 /= Tc_Rec1 (2))
               or else (Sale_Rec_02.Buyer /= Tc_Rec1 (2).Buyer)
               or else (Product_01_Stats /= Tc_Stat1))
            then
               Report.Failed ("Product 1 information incorrect");
            end if;

            -- Verify the information of the second product.
            if not
              ((Product_02 = Tc_Product2) and then (Sale_Count_02 = Tc_Count2)
               and then (Product_02_Stats = Tc_Stat2))
            then
               Report.Failed ("Product 2 information incorrect");
            end if;

            -- Verify the information of the third product.
            if
              ((Product_03 /= Tc_Product3)
               or else (Product_03.Manufacture /= Tc_Product3.Manufacture)
               or else (Sale_Count_03 /= Tc_Count3)
               or else (Sale_Rec_03 /= Tc_Rec3 (1))
               or else (Sale_Rec_03.Buyer /= Tc_Rec3 (1).Buyer)
               or else (Sale_Rec_04 /= Tc_Rec3 (2))
               or else (Sale_Rec_04.Buyer /= Tc_Rec3 (2).Buyer)
               or else (Sale_Rec_05 /= Tc_Rec3 (3))
               or else (Sale_Rec_05.Buyer /= Tc_Rec3 (3).Buyer)
               or else (Product_03_Stats /= Tc_Stat3))
            then
               Report.Failed ("Product 3 information incorrect");
            end if;

         end Verify_Data_Block;

      exception

         when others =>
            Report.Failed ("Exception raised in Operational Test Block");

      end Operational_Test_Block;

      if Ada.Streams.Stream_Io.Is_Open (Info_File) then
         Ada.Streams.Stream_Io.Delete (Info_File);
      else
         Ada.Streams.Stream_Io.Open
           (Info_File, Ada.Streams.Stream_Io.In_File, The_Filename);
         Ada.Streams.Stream_Io.Delete (Info_File);
      end if;

   exception

      -- Since Use_Error or Name_Error can be raised if, for the specified
      -- mode, the environment does not support Stream_IO operations, the
      -- following handlers are included:

      when Ada.Streams.Stream_Io.Name_Error =>
         Report.Not_Applicable ("Name_Error raised on Stream IO Create");

      when Ada.Streams.Stream_Io.Use_Error =>
         Report.Not_Applicable ("Use_Error raised on Stream IO Create");

      when others =>
         Report.Failed ("Unexpected exception raised on Stream IO Create");

   end Test_For_Stream_Io_Support;

   Report.Result;

end Cxaca01;
