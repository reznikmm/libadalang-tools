--=======================================================================--

procedure Fa11d00
  .Ca11d011
  (Left, Right : in     Complex_Type;
   C           :    out Complex_Type)
is
-- Multiply_Complex.

begin
   -- Zero is declared in parent package.

   if Left.Real < Zero.Real or Right.Imag < Zero.Imag then
      raise Multiply_Error;  -- Reference to exception in parent package.
      Report.Failed
        ("Program control not transferred by raise in " &
         "child procedure FA11D00.CA11D011");
   else
      C.Real := (Left.Real * Right.Real);
      C.Imag := (Left.Imag * Right.Imag);
   end if;

exception
   when others =>
      Tc_Handled_In_Child_Sub := True;
      C := Check_Value;            -- Reference to object in parent package.

end Fa11d00.Ca11d011;     -- Multiply_Complex
