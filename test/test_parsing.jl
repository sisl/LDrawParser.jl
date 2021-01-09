let
    @test LDrawParser.parse_meta_command(["0", "ROTSTEP", "END"]) == LDrawParser.ROTSTEP_END
    @test LDrawParser.parse_meta_command(["0", "ROTSTEP", ""]) == LDrawParser.ROTSTEP_BEGIN
    @test LDrawParser.parse_meta_command(["0", "STEP", ""]) == LDrawParser.STEP
end
