-----------------------------------------------------------------------------

with Cxe4005_Part_A1;
with Cxe4005_Part_A2;
with Cxe4005_Normal;
with Cxe4005_Remote_Types;
with Report;
package body Cxe4005_Part_B is

   type Not_Available_For_Remote_Call is new Cxe4005_Common
     .Root_Tagged_Type with
   null record;

   Root_Obj       : aliased Cxe4005_Common.Root_Tagged_Type;
   Rt_Obj         : aliased Cxe4005_Remote_Types.Rt_Tagged_Type;
   Local_Only_Obj : aliased Not_Available_For_Remote_Call;
   Normal_Obj     : aliased Cxe4005_Normal.Cant_Use_In_Remote_Call;

   -- provide access to a remote access value
   function Get_Racwt
     (Which_Type : Type_Selection) return Cxe4005_Part_A1.Racwt
   is
   begin
      case Which_Type is
         when Common_Spec =>
            return Root_Obj'Access;
         when Rt_Spec =>
            return Rt_Obj'Access;
         when B_Body =>
            return Local_Only_Obj'Access;
         when Normal_Spec =>
            return Normal_Obj'Access;
      end case;
   end Get_Racwt;

begin
   Cxe4005_Common.Set_Serial_Number (Root_Tagged_Type (Root_Obj)'Access, 301);
   Cxe4005_Common.Set_Serial_Number (Root_Tagged_Type (Rt_Obj)'Access, 306);
   Cxe4005_Common.Set_Serial_Number
     (Root_Tagged_Type (Local_Only_Obj)'Access, 307);
   Cxe4005_Common.Set_Serial_Number
     (Root_Tagged_Type (Normal_Obj)'Access, 308);
end Cxe4005_Part_B;
