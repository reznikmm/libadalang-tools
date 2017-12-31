     --=================================================================--
with Report;

-- Child library subprogram Convert_File_Mode body.
procedure Ca11002_0.Ca11002_2 (File : in out File_Type;
   New_Mode                         : in     File_Mode)
is
begin
   if File.Mode = New_Mode then
      raise File_Mode_Error;                               -- Parent exception.
      Report.Failed ("Exception not raised in child unit");
   else
      File.Mode := New_Mode;
   end if;
end Ca11002_0.Ca11002_2;
