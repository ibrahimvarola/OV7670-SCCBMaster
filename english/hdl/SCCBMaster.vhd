---------------------------------------------------------------------------------------------------------------------------------------------
--  OV7670 uses SCCB interface for configuring it's registers. That interface is compatible with I2C. 
--  But unlike I2C, SCCB has logical-1 state on it's data line.
--  High - Low - High Impedance
--
--  The most important point of this interface is; ACK and NACK bits are useless in write mode. SCCB 
--  uses a "Don't Care" bit. That bit is logical-0. You can see the data frame of a write process:
--
--      |A6|A5|A4|A3|A2|A1|A0|R/W|DC|-|R7|R6|R5|R4|R3|R2|R1|R0|DC|-|D7|D6|D5|D4|D3|D2|D1|D0|DC|
--             7-bit Address               8-Bit Register/Data             8-bit Data
--         R => logical-1
--         W => logical-0
--
--  Warning: This module made for only writing data to registers. Read process will be added. :)
--
--  
--  Used Sources         : OV7670 Datasheet
--                       : OmniVision SCCB Specification
--                       : http://www.dejazzer.com/hardware.html (Face detection on FPGA: OV7670 CMOS camera + DE2-115 FPGA board)
--                       : http://www.dejazzer.com/eigenpi/digital_camera/digital_camera.html
--
--
---------------------------------------------------------------------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use IEEE.NUMERIC_STD.all;

entity SCCBMaster is
    generic(
        GInputClock :   integer := 50_000_000;                  --  FPGA main clock speed
        GBusClock   :   integer := 400_000                      --  Speed of SCCB clock to be used
    );          
	port(       
		PIClock     :   in      std_logic;                      --  System clock input
        PIReset     :   in      std_logic;                      --  Reset(active low) input
        PIEnable    :   in      std_logic;                      --  Enable input that enables the SCCB interface
        PIAddress   :   in      std_logic_vector(6 downto 0);   --  SCCB slave device's address input
        PIRegister  :   in      std_logic_vector(7 downto 0);   --  SCCB slave device's register input
        PIWriteData :   in      std_logic_vector(7 downto 0);   --  Data input
        PIStart     :   in      std_logic;                      --  Module's backend start input
        PODone      :   out     std_logic;                      --  Gives an logical-1 output when the process is complete
        POReady     :   out     std_logic;                      --  Output for determine SCCB line is ready for another operation
        PIOSIOD     :   inout   std_logic;                      --  SCCB serial data I/O
        POSIOC      :   out     std_logic                       --  SCCB clock output
	);
end SCCBMaster;

architecture Behavioral of SCCBMaster is

------------------------------------------------------------------------------------------------------------------
--  In this step; signals and state machine states created for I/O ports and references.
------------------------------------------------------------------------------------------------------------------

    type        TStatesWrite        is  (idle, start_condition, send_addr, addr_dc, send_reg, reg_dc, send_data, data_dc, stop);
    signal      SStateWriteBase     :   TStatesWrite                        :=  idle;
    
    constant    CClockCountMax      :   integer                             :=  (GInputClock / GBusClock);
    
    signal      SStart              :   std_logic                           :=  '0';
    signal      SStartReg           :   std_logic                           :=  '0';
    signal      SStartedWrite       :   std_logic                           :=  '0';  

    signal      SEnable             :   std_logic                           :=  '0';
    signal      SAddress            :   std_logic_vector(6 downto 0)        :=  (others => '0');
    signal      SRegister           :   std_logic_vector(7 downto 0)        :=  (others => '0');
    signal      SWriteData          :   std_logic_vector(7 downto 0)        :=  (others => '0');
    signal      SBusy               :   std_logic                           :=  '0';    
    signal      SBusy2              :   std_logic                           :=  '0';               
    signal      SDone               :   std_logic                           :=  '0';
    signal      SReady              :   std_logic                           :=  '0';

    signal      SDataClockRef       :   std_logic                           :=  '0';
    signal      SDataClockRefPrev   :   std_logic                           :=  '0';
    
    -- signal      SSIODClock          :   std_logic                        :=    '0';   --  DEBUG ONLY!
    -- signal      SSIODClockPrev      :   std_logic;                                    --  DEBUG ONLY!
    signal      SSIOCClock          :   std_logic                           :=  '1';
    signal      SSIOCClockPrev      :   std_logic;      
    
    signal      SSIODWrite          :   std_logic                           :=  '0';
    signal      SSIODRead           :   std_logic                           :=  '0';
    signal      SSIOCWrite          :   std_logic                           :=  '0';
    signal      SSIOCRead           :   std_logic                           :=  '0';  
    
    signal      SAddr               :   std_logic_vector(6 downto 0)        :=  (others => '0');
    signal      SReg                :   std_logic_vector(7 downto 0)        :=  (others => '0');
    signal      SData               :   std_logic_vector(7 downto 0)        :=  (others => '0');
    
    signal      SAddrReg            :   std_logic_vector(6 downto 0)        :=  (others => '0');
    signal      SRegReg             :   std_logic_vector(7 downto 0)        :=  (others => '0');
    signal      SDataReg            :   std_logic_vector(7 downto 0)        :=  (others => '0'); 
    signal      SCounter            :   integer range 0 to 8                :=  0;

    signal      SCounterSCCB        :   integer range 0 to CClockCountMax   :=  0;
    signal	    SCounter2           :	integer range 0 to 3                :=  0;
    

begin

------------------------------------------------------------------------
--  In this part; the I/O ports are directed to according signals
------------------------------------------------------------------------
    SStart      <=  PIStart;
    SEnable     <=  PIEnable;
    SAddress    <=  PIAddress;  
    SRegister   <=  PIRegister; 
    SWriteData  <=  PIWriteData;
    PODone      <=  SDone;
    POReady     <=  SReady;	

    POSIOC      <=  SSIOCWrite when (SStateWriteBase = idle or SStateWriteBase = start_condition or SStateWriteBase = stop ) else
                    SSIOCClock;

    PIOSIOD     <=  SSIODWrite when SEnable = '1' else 'Z';

    SStartReg   <=  '1' when SStart = '1' and SEnable = '1' else
                    '0' when (SSIOCClock = '0' and SSIOCClockPrev = '1') or PIReset = '0' or SEnable = '0' else
                    SStartReg;

-------------------------------------------------------------------------------------------------------------------------------
--  READY process; if write operation is over (SDone == '1') and write state machine is at start(SStateWriteBase == idle)
--  then it changes SReady to logic-1. And when the system at reset state(PIReset == '0') it changes SReady to logic-0.
-------------------------------------------------------------------------------------------------------------------------------
    READY : process(PIClock, PIReset)
    begin
        if PIReset = '0' then
            SReady      <= '0';
        elsif rising_edge(PIClock) then
            if SStateWriteBase = idle then
                SReady  <= '1';
            else
                SReady  <= '0';
            end if;
        end if;
    end process;

-------------------------------------------------------------------------------------------------------------------------------
--  According to SStart signal state, this process; it assigns address, register and data inputs into their "register" 
--  signals. When the system triggered by the reset input, all the register signals will be cleared.
-------------------------------------------------------------------------------------------------------------------------------

    DATA_CAPTURE : process(PIClock, PIReset)
    begin
        if PIReset = '0' then
            SAddrReg        <= (others => '0');
            SRegReg         <= (others => '0');
            SDataReg        <= (others => '0');
        elsif rising_edge(PIClock) then
            if SStart = '1' then
                SAddrReg    <= SAddress;
                SRegReg     <= SRegister;
                SDataReg    <= SWriteData;
            elsif SSIOCClock = '0' and SSIOCClockPrev = '1' then
                SAddrReg    <= SAddrReg;
                SRegReg     <= SRegReg; 
                SDataReg    <= SDataReg;
            else
                SAddrReg    <= SAddrReg;
                SRegReg     <= SRegReg; 
                SDataReg    <= SDataReg;
            end if;
        end if;
    end process;

-------------------------------------------------------------------------------------------------------------------------------
--  CLKGEN process; generates clock reference signals for SCCB interface. The important thing at this point is:
--  If we inspect the datasheet of the OV7670, we can see data changes at half of the period of SCCB's logic-0.  
--  For that reason we need to create a data reference signal that changes at half of the period of SIOC reference signal.
--  
--  |¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______    =====>>>    SIOC Reference Clock
--              |               |               |               |               |
--              |               |               |               |               |
--  |¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_    =====>>>    DATA Reference Clock
--  
-------------------------------------------------------------------------------------------------------------------------------
    CLKGEN : process(PIClock)
        variable    VCounter        : integer range 0 to CClockCountMax     := 0;
    begin
        if rising_edge(PIClock) then
            --SSIODClockPrev      <= SSIODClock;
            SSIOCClockPrev      <= SSIOCClock;
            SDataClockRefPrev   <=  SDataClockRef;
            
				if SCounterSCCB = (CClockCountMax / 4) - 1 then
					SDataClockRef   <= not SDataClockRef;
					if SCounter2 = 1 then
						--SSIODClock  <= not SSIODClock;
						SSIOCClock   <= not SSIOCClock;
						SCounter2 <= 0;
					else
						SCounter2 <= SCounter2 + 1;
					end if;
					SCounterSCCB	<= 0;
				else
					SCounterSCCB    <= SCounterSCCB +1;
				end if;

        end if;
    end process;

-------------------------------------------------------------------------------------------------------------------------------------------
--  DATA_WRITE process; It contains the state machine that will write in accordance with the SCCB interface. When PIReset input trig-
--  gered, all of the states, signals and registers will be cleared.
--
--                                                           !!!!IMPORTANT!!!!
--
--  When the SCCB interface at the idle state, it will hold the SIOD output at high impedance and SIOC output at logic-1 state. Start
--  condition changes the SIOD line to logic-1 and after half of the SIOC referance period, changes the SIOC line to logic-0 to start
--  communication. The finish state is; when there is no data to be written, firstly changes the SIOC line to logic-1 state and after
--  half of the SIOC referance period, the SIOD line will be changed to high impedance state. But if there is another data needs to
--  be written, then SIOD line will be changed to logic-1 state.
--
--
--  SIOD     -------¯¯¯¯¯¯¯|                               |¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|               |¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|
--                         |_______________________________|               |_______________|                               |______
--                         |               |               |               |               |               |               |
--                         |               |               |               |               |               |               |
--                         |               |               |               |               |               |               |  
--  SIOC     ¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|               |¯¯¯¯¯¯¯|   |   |¯¯¯¯¯¯¯|   |   |¯¯¯¯¯¯¯|   |   |¯¯¯¯¯¯¯|   |   |¯¯¯¯¯¯¯|   |    
--                             |_______________|       |_______|       |_______|       |_______|       |_______|       |___|______
--                         |               |               |               |               |               |               |
--                         |               |               |               |               |               |               |
--  SIOC Ref   |¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______ 
--                         |               |               |               |               |               |               |
--                         |               |               |               |               |               |               |
--  SIOD Ref   |¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_            
--
-------------------------------------------------------------------------------------------------------------------------------------------

    DATA_WRITE : process(PIClock, PIReset)
        variable VCounter : integer range 0 to 16 := 0;
    begin
        if PIReset = '0' then
            SStateWriteBase <= idle;
            SStartedWrite   <= '0';
            SAddr           <= (others => '0');
            SReg            <= (others => '0');
            SData           <= (others => '0');
            SSIODWrite      <= 'Z';
            SSIOCWrite      <= '1';
            SBusy           <= '0';
            SDone           <= '0';
            SBusy2          <= '0';
            VCounter        := 0;
            SCounter        <=  7;
        elsif rising_edge(PIClock) then
            case SStateWriteBase is
-------------------------------------------------------------------------------------------------------------------------------------------
--  "idle" state; when SStartReg is triggered; takes address, register and write data to cache and changes the it's state to 
--  "start_condition" at rising edge of SIOC reference clock.
--  If SStartReg signal is not triggered(SIOD = 'Z' - SIOC = '1'), then system will remain in the "idle" state.
-------------------------------------------------------------------------------------------------------------------------------------------
                when idle =>
                    if SSIOCClock = '0' and SSIOCClockPrev = '1' then
                        if SStartReg = '1' then
                            SSIODWrite   <= '1';
                            SSIOCWrite   <= '1';
                            SStartedWrite    <= '1';
                            SDone       <= '0';
                            SAddr       <= SAddrReg;
                            SReg        <= SRegReg;
                            SData       <= SDataReg;
                        else
                            SAddr       <= (others => '0');
                            SReg        <= (others => '0');
                            SData       <= (others => '0');
                            SStateWriteBase      <= idle;
                            SSIODWrite   <= 'Z';
                            SSIOCWrite   <= '1';
                            SStartedWrite    <= '0';
                            SDone       <= '1';
                        end if;
                    elsif SSIOCClock = '1' and SSIOCClockPrev = '0' and SStartedWrite = '1' then    
                        SSIODWrite   <= '0';
                        
                        SStartedWrite    <= '0';
                        SStateWriteBase <= start_condition;
                    end if;
-------------------------------------------------------------------------------------------------------------------------------------------
--  start_condition" state; after 2 SIOC reference clock pulse, it writes the cached address data's first bit to SIOD line while shifting
--  cached address data to left when rising edge of SIOD reference and SIOC reference is logic-0. After that the state will change to
--  "send_addr" state.
-------------------------------------------------------------------------------------------------------------------------------------------
                when start_condition =>
                    if SSIOCClock = '0' and SSIOCClockPrev = '1' then
                        SBusy <= '1';
                        if SBusy = '1' then
                            SBusy2 <= '1';
                        end if;
                        SSIOCWrite   <= '0';
                    elsif SDataClockRef = '1' and SDataClockRefPrev = '0' and SSIOCClock = '0' and SBusy2 = '1' then
                        if SAddr(6) = '1' then
                            SSIODWrite <= '1';
                            SAddr <= std_logic_vector(shift_left(unsigned(SAddr), 1));
                        elsif SAddr(6) = '0' then
                            SSIODWrite <= '0';
                            SAddr <= std_logic_vector(shift_left(unsigned(SAddr), 1));
                        end if;
                        SBusy   <= '0';
                        SBusy2   <= '0';                            
                        SStateWriteBase      <= send_addr;

                        
                    else
                        SStateWriteBase      <= start_condition;
                    end if;
-------------------------------------------------------------------------------------------------------------------------------------------
--  "send_addr" state; writes the remaining address data to SIOD line and writes the "Don't Care" bit (logic-0) to SIOD line when rising 
--  edge of SIOD reference clock and at SIOC reference clock is 0.
-------------------------------------------------------------------------------------------------------------------------------------------                    
                when send_addr =>
                    if SDataClockRef = '1' and SDataClockRefPrev = '0' and SSIOCClock = '0' then
                        if VCounter <= 5 then
                            VCounter    := VCounter + 1;
                            if(SAddr(6) = '1') then
                                SSIODWrite   <= '1';
                                SAddr       <= std_logic_vector(shift_left(unsigned(SAddr), 1));
                            elsif (SAddr(6) = '0') then
                                SSIODWrite   <= '0';
                                SAddr       <= std_logic_vector(shift_left(unsigned(SAddr), 1));
                            end if;
                        else
                            VCounter    := 0;
                            SSIODWrite   <= '0'; ---->>>> Don't Care Bit!
                            SStateWriteBase      <= addr_dc;
                            SBusy       <= '0';
                        end if;
                    else
                        SStateWriteBase      <= send_addr;
                    end if;

                when addr_dc =>
                    if SDataClockRef = '1' and SDataClockRefPrev = '0' and SSIOCClock = '0' then
                        SAddr   <=  (others => '0');
                    elsif SDataClockRef = '0' and SDataClockRefPrev = '1' and SSIOCClock = '0' then
                        SStateWriteBase      <= send_reg;
                    end if;
-------------------------------------------------------------------------------------------------------------------------------------------
--  "send_reg" state; It writes the register data to the SIOD line as soon as the rising edge of the SIOD reference and the SIOC 
--  reference are logic-0. After finishing writing register data, it will write a "Don't Care" bit.
-------------------------------------------------------------------------------------------------------------------------------------------   
                when send_reg =>
                    if SDataClockRef = '1' and SDataClockRefPrev = '0' and SSIOCClock = '0' then
                        SBusy <= '1';
                        if SBusy = '1' then
                            if VCounter <= 7 then
                                VCounter    := VCounter + 1;
                                if(SReg(7) = '1') then
                                    SSIODWrite   <= '1';
                                    SReg        <= std_logic_vector(shift_left(unsigned(SReg), 1));
                                elsif (SReg(7) = '0') then
                                    SSIODWrite   <= '0';
                                    SReg        <= std_logic_vector(shift_left(unsigned(SReg), 1));
                                end if;
                            else
                                SBusy <= '0';
                                VCounter    := 0;
                                SSIODWrite   <= '0'; ---->>>> Don't Care Bit!
                                SStateWriteBase      <= reg_dc;
                            end if;
                        end if;
                    end if;
-------------------------------------------------------------------------------------------------------------------------------------------
--  "reg_dc" state; after "Don't Care" bit is written, like the other states, according SIOD and SIOC reference states it will write 
--  the cached data's first bit while shifting to the left to SIOD line and changes it's state to "send_data".
-------------------------------------------------------------------------------------------------------------------------------------------   
                when reg_dc =>
                    if SDataClockRef = '1' and SDataClockRefPrev = '0' and SSIOCClock = '0' then
                        SReg   <=  (others => '0');
                        SStateWriteBase      <= send_data;
                        if(SData(7) = '1') then
                            SSIODWrite   <= '1';
                            SData       <= std_logic_vector(shift_left(unsigned(SData), 1));
                            SBusy <= '0';
                        elsif (SData(7) = '0') then
                            SSIODWrite   <= '0';
                            SData       <= std_logic_vector(shift_left(unsigned(SData), 1));
                            SBusy <= '0';
                        end if;
                    end if;
-------------------------------------------------------------------------------------------------------------------------------------------
--  "send_data" state; when the first bit of the data is written, the remaining bits will be written to the SIOD line while shifting
--  to the left. When data write is done, it will write "Don't Care" bit to SIOD line and after 1 SIOD and SIOC reference clock it
--  will change it's state to "data_dc".
-------------------------------------------------------------------------------------------------------------------------------------------   
                when send_data =>
                    if SDataClockRef = '1' and SDataClockRefPrev = '0' and SSIOCClock = '0' then
                        if VCounter     <= 6 then
                            VCounter    := VCounter + 1;
                            if(SData(7) = '1') then
                                SSIODWrite   <= '1';
                                SData       <= std_logic_vector(shift_left(unsigned(SData), 1));
                            elsif (SData(7) = '0') then
                                SSIODWrite   <= '0';
                                SData       <= std_logic_vector(shift_left(unsigned(SData), 1));
                            end if;
                        else
                            
                            SSIODWrite   <= '0'; ----
                            SBusy <= '1';
                            if SBusy = '1' then
                                VCounter    := 0;
                                SStateWriteBase      <= data_dc;
                                SBusy <= '0';
                            end if;
                            
                        end if;
                    end if;
----------------------------------------------------------------------------------------------
--  "data_dc" state; waits only one SIOC reference clock and change it's state to "stop".
----------------------------------------------------------------------------------------------
                when data_dc =>
                    if SSIOCClock = '1' and SSIOCClockPrev = '0' then
                        SData      <= (others => '0');
                        SStateWriteBase <= stop;
                    end if;
-------------------------------------------------------------------------------------------------------------------------------------------
--  "stop" state; for stopping the SCCB communication, firstly changes SIOC line to logic-1 state and after 1 SIOC reference clock, it
--  changes the SIOD line to logic-1 state and goes to "idle" state.
-------------------------------------------------------------------------------------------------------------------------------------------   
                when stop =>
                    SSIOCWrite   <= '1';
                    if SSIOCClock = '1' and SSIOCClockPrev = '0' then
                          SSIODWrite   <= '1';
                        SBusy       <= '1';
                        SAddr       <= (others => '0');
                        SReg        <= (others => '0');
                        SData       <= (others => '0');
                        if SBusy = '1' then
                            --SReady      <= '1';
                            SStateWriteBase      <= idle;
                            SDone       <= '1';
                        
                            SBusy       <= '0';
                        end if;
                    elsif SSIOCClock = '0' and SSIOCClockPrev = '1' then
                        SSIODWrite   <= '1';
                    end if;

                when others =>
            end case;
        end if;
    end process;

end Behavioral;
