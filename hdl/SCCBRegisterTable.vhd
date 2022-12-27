library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use IEEE.NUMERIC_STD.all;

entity SCCBRegisterTable is
    port (
        PIClock         : in    std_logic;
        PIReset         : in    std_logic;
        PITrig          : in    std_logic;
        PIDone          : in    std_logic;
        PIReady         : in    std_logic;
        POCfgFinished   : out   std_logic;
        POStart         : out   std_logic;
        POEnable        : out   std_logic;
        POAddress       : out   std_logic_vector(6 downto 0);
        PORegister      : out   std_logic_vector(7 downto 0);
        POWriteData     : out   std_logic_vector(7 downto 0)
    );

end SCCBRegisterTable;

architecture Behavioral of SCCBRegisterTable is
    constant    CDeviceBaseAddress  :   std_logic_vector(7 downto 0)    := x"21";
    constant    CDeviceWriteAddress :   std_logic_vector(7 downto 0)    := x"42";
    constant    CDeviceReadAddress  :   std_logic_vector(7 downto 0)    := x"43";

    

    signal      STrig               :   std_logic                       := '0';
    signal      SDone               :   std_logic                       := '0';
    signal      SReady              :   std_logic                       := '0';
    signal      SCfgFinished        :   std_logic                       := '0';
    signal      SStart              :   std_logic                       := '0';
    signal      SEnable             :   std_logic                       := '0';
    signal      SAddress            :   std_logic_vector(6 downto 0)    := (others => '0');
    signal      SRegister           :   std_logic_vector(7 downto 0)    := (others => '0');
    signal      SWriteData          :   std_logic_vector(7 downto 0)    := (others => '0');
	 

    signal      STrigPrev           :   std_logic                       := '0';
    signal      STrigRising         :   std_logic                       := '0';
    signal      STrigFalling        :   std_logic                       := '0';

    signal      SReadyPrev          :   std_logic                       := '0';
    signal      SReadyRising        :   std_logic                       := '0';

    signal      SCounter            :   integer range 0 to 58           := 0;

	 
    signal      SWaitCtr            :   integer range 0 to 255				:= 0;

    
begin
    STrig           <=  PITrig;
    SDone           <=  PIDone;
    SReady          <=  PIReady;

    POCfgFinished   <=  SCfgFinished;
    POStart         <=  SStart;    
    POEnable        <=  SEnable;   
    POAddress       <=  SAddress;  
    PORegister      <=  SRegister; 
    POWriteData     <=  SWriteData;

    READY_EDGE : process(PIClock, PIReset)
    begin
        if PIReset = '0' then
            SReadyPrev      <= '0';
            SReadyRising    <= '0';
        elsif rising_edge(PIClock) then
            SReadyPrev  <= SReady;
            if SReady = '1' and SReadyPrev = '0' then
                SReadyRising <= '1';
            else
                SReadyRising <= '0';
            end if;
        end if;
    end process;

    TRIG_EDGES :   process(PIClock, PIReset)
    begin
        if PIReset = '0' then
            STrigPrev       <= '0';
            STrigRising     <= '0';
            STrigFalling    <= '0';
        elsif rising_edge(PIClock) then
            STrigPrev   <= STrig;
            if STrig = '1' and STrigPrev = '0' then
                STrigRising     <= '1';
            else
                STrigRising     <= '0';
            end if;
            
            if STrig = '0' and STrigPrev = '1' then
                STrigFalling    <= '1';
            else
                STrigFalling    <= '0';
            end if;
        end if;
    end process;

    BACKEND :   process(PIClock, PIReset)
    begin
        if PIReset = '0' then
            SCfgFinished    <= '0';
            SStart          <= '0';
            SEnable         <= '0';
            SAddress        <= (others => '0');
            SRegister       <= (others => '0');
            SWriteData      <= (others => '0');
            SCounter        <= 0;
        elsif rising_edge(PIClock) then
			if SWaitCtr <= 254 then
				SWaitCtr <= SWaitCtr + 1;
			else
                if (SReady = '1' and STrigFalling = '1' and SStart = '0') or (SStart = '1' and SReadyRising = '1') then
                    SEnable     <=  '1';
                    SStart      <=  '1';
                    SAddress    <=  CDeviceBaseAddress(6 downto 0);
                    if SCounter <= 56 then
                        SCounter    <= SCounter + 1;
                        case SCounter is
                            when 0 =>
                                SRegister   <= x"12";
                                SWriteData  <= x"80";
                            when 1 =>   
                                
                                SRegister   <= x"12";
                                SWriteData  <= x"80";
                            when 2 =>   
                                SRegister   <= x"12";
                                SWriteData  <= x"04";
                            when 3 =>   
                                SRegister   <= x"11";
                                SWriteData  <= x"00";
                            when 4 =>   
                                SRegister   <= x"0C";
                                SWriteData  <= x"00";
                            when 5 =>   
                                SRegister   <= x"3E";
                                SWriteData  <= x"00";
                            when 6 =>   
                                SRegister   <= x"8C";
                                SWriteData  <= x"00";
                            when 7 =>   
                                SRegister   <= x"04";
                                SWriteData  <= x"00";
                            when 8 =>   
                                SRegister   <= x"40";
                                SWriteData  <= x"10";
                            when 9 =>   
                                SRegister   <= x"3A";
                                SWriteData  <= x"04";
                            when 10 =>  
                                SRegister   <= x"14";
                                SWriteData  <= x"38";
                            when 11 =>  
                                SRegister   <= x"4F";
                                SWriteData  <= x"40";
                            when 12 =>  
                                SRegister   <= x"50";
                                SWriteData  <= x"34";
                            when 13 =>  
                                SRegister   <= x"51";
                                SWriteData  <= x"0C";
                            when 14 =>  
                                SRegister   <= x"52";
                                SWriteData  <= x"17";
                            when 15 =>  
                                SRegister   <= x"53";
                                SWriteData  <= x"29";
                            when 16 =>  
                                SRegister   <= x"54";
                                SWriteData  <= x"40";
                            when 17 =>  
                                SRegister   <= x"58";
                                SWriteData  <= x"1E";
                            when 18 =>  
                                SRegister   <= x"3D";
                                SWriteData  <= x"C0";
                            when 19 =>  
                                SRegister   <= x"11";
                                SWriteData  <= x"00";
                            when 20 =>  
                                SRegister   <= x"17";
                                SWriteData  <= x"11";
                            when 21 =>  
                                SRegister   <= x"18";
                                SWriteData  <= x"61";
                            when 22 =>  
                                SRegister   <= x"32";
                                SWriteData  <= x"A4";
                            when 23 =>  
                                SRegister   <= x"19";
                                SWriteData  <= x"03";
                            when 24 =>  
                                SRegister   <= x"1A";
                                SWriteData  <= x"7B";
                            when 25 =>  
                                SRegister   <= x"03";
                                SWriteData  <= x"0A";
                            when 26 =>  
                                SRegister   <= x"0E";
                                SWriteData  <= x"61";
                            when 27 =>  
                                SRegister   <= x"0F";
                                SWriteData  <= x"4B";
                            when 28 =>  
                                SRegister   <= x"16";
                                SWriteData  <= x"02";
                            when 29 =>  
                                SRegister   <= x"1E";
                                SWriteData  <= x"37";
                            when 30 =>  
                                SRegister   <= x"21";
                                SWriteData  <= x"02";
                            when 31 =>  
                                SRegister   <= x"22";
                                SWriteData  <= x"91";
                            when 32 =>  
                                SRegister   <= x"29";
                                SWriteData  <= x"07";
                            when 33 =>  
                                SRegister   <= x"33";
                                SWriteData  <= x"0B";
                            when 34 =>  
                                SRegister   <= x"35";
                                SWriteData  <= x"0B";
                            when 35 =>  
                                SRegister   <= x"37";
                                SWriteData  <= x"1D";
                            when 36 =>  
                                SRegister   <= x"38";
                                SWriteData  <= x"71";
                            when 37 =>  
                                SRegister   <= x"39";
                                SWriteData  <= x"2A";
                            when 38 =>  
                                SRegister   <= x"3C";
                                SWriteData  <= x"78";
                            when 39 =>  
                                SRegister   <= x"4D";
                                SWriteData  <= x"40";
                            when 40 =>  
                                SRegister   <= x"4E";
                                SWriteData  <= x"20";
                            when 41 =>  
                                SRegister   <= x"69";
                                SWriteData  <= x"00";
                            when 42 =>  
                                SRegister   <= x"6B";
                                SWriteData  <= x"4A";
                            when 43 =>  
                                SRegister   <= x"74";
                                SWriteData  <= x"10";
                            when 44 =>  
                                SRegister   <= x"8D";
                                SWriteData  <= x"4F";
                            when 45 =>  
                                SRegister   <= x"8E";
                                SWriteData  <= x"00";
                            when 46 =>  
                                SRegister   <= x"8F";
                                SWriteData  <= x"00";
                            when 47 =>  
                                SRegister   <= x"90";
                                SWriteData  <= x"00";
                            when 48 =>  
                                SRegister   <= x"91";
                                SWriteData  <= x"00";
                            when 49 =>  
                                SRegister   <= x"96";
                                SWriteData  <= x"00";
                            when 50 =>  
                                SRegister   <= x"9A";
                                SWriteData  <= x"00";
                            when 51 =>  
                                SRegister   <= x"B0";
                                SWriteData  <= x"84";
                            when 52 =>  
                                SRegister   <= x"B1";
                                SWriteData  <= x"0C";
                            when 53 =>  
                                SRegister   <= x"B2";
                                SWriteData  <= x"0E";
                            when 54 =>  
                                SRegister   <= x"B3";
                                SWriteData  <= x"82";
                            when 55 =>  
                                --SStart      <=  '0';
                                --SEnable     <=  '0';
                                --SCfgFinished    <= '1';
                                --SCounter        <= 0;
                                SRegister   <= x"B8";
                                SWriteData  <= x"0A";
                                
                            when others =>  
                                SRegister       <= x"FF";
                                SWriteData      <= x"FF";
                                SMode       <= '0';
                                SStart          <=  '0';
                                SEnable         <= '0';
                                SCfgFinished    <= '1';
                                SCounter        <= 0;
                    end case;
                    else
                        SAddress    <=  SAddress;
                        SEnable     <=  SEnable;
                        SStart      <=  '0';
                        SCounter    <= 0;
                        SRegister   <=  SRegister; 
                        SWriteData  <=  SWriteData;
                    end if;
                else
                    SAddress    <=  SAddress;
                    SEnable     <=  SEnable;
                    SStart      <=  SStart;
                    SRegister   <=  SRegister; 
                    SWriteData  <=  SWriteData;
                end if;
            end if;
        end if;
    end process;

end Behavioral;
