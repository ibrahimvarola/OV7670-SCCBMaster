---------------------------------------------------------------------------------------------------------------------------------------------
--  OV7670 kamera modulu ayarlarinin yapilmasi icin SCCB protokolunu kullanir. Bu protokol I2C uyumludur. 
--  SCCB protokolu I2C'den farkli olarak lojik-1 durumuna da sahiptir.
--  High - Low - High Impedance
--
--  Bu protokolun en onemli noktasi; ACK ve NACK bitleri yazma islemi icin gereksizdir. Bu bitler yerine
--  "Don't Care" isimli lojik-0 biti kullanılır. Asagida ornek bir yazma isleminin veri paketi gorulmektedir:
--
--      |A6|A5|A4|A3|A2|A1|A0|R/W|DC|-|R7|R6|R5|R4|R3|R2|R1|R0|DC|-|D7|D6|D5|D4|D3|D2|D1|D0|DC|
--             7-bit Address               8-Bit Register/Data             8-bit Data
--         R => lojik-1
--         W => lojik-0
--  
--  SCCB hattindan sadece veri gonderileceginden sadece WRITE islemi eklenmistir. OV7670 kamera modulu paralel
--  8-bit kamera veri hatti bulunduruyor. Bu noktada READ adimi eklenmedi!
--  
--  Kullanilan kaynaklar : OV7670 Datasheet
--                       : OmniVision SCCB Specification
--                       : http://www.dejazzer.com/hardware.html (Face detection on FPGA: OV7670 CMOS camera + DE2-115 FPGA board)
--                       : http://www.dejazzer.com/eigenpi/digital_camera/digital_camera.html
--
--  TODO => Aciklamalari Ingilizce yap!
--
---------------------------------------------------------------------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use IEEE.NUMERIC_STD.all;

entity SCCBMaster is
    generic(
        GInputClock :   integer := 50_000_000;                  --  FPGA' nin ana clock hizi
        GBusClock   :   integer := 400_000                      --  SCCB hattinin calistirilmasi icin belirlenecek hiz (400 kHz SCCB fast mode)
    );          
	port(       
		PIClock     :   in      std_logic;                      --  Sistem clock girisi
        PIReset     :   in      std_logic;                      --  Reset(active low) girisi
        PIEnable    :   in      std_logic;                      --  SCCB hattini aktif edecek enable girisi
        PIAddress   :   in      std_logic_vector(6 downto 0);   --  SCCB hattina bagli olan slave cihazlarinin ana adreslerini isaret eden giris
        PIRegister  :   in      std_logic_vector(7 downto 0);   --  Slave birimin islem yapilacak register adresini belirten giris
        PIWriteData :   in      std_logic_vector(7 downto 0);   --  Master -> Slave yonunde yazilacak data
        PIStart     :   in      std_logic;                      --  SCCB master backend calistirma girisi
        PODone      :   out     std_logic;                      --  SCCB arayuzunun yazma islemini bitirdigini belirten cikis
        POReady     :   out     std_logic;                      --  SCCB arayuzunun islem yapmaya hazir oldugunu belirten cikis
        PIOSIOD     :   inout   std_logic;                      --  SCCB seri data cikisi - girisi
        POSIOC      :   out     std_logic                       --  SCCB seri clock cikisi
	);
end SCCBMaster;

architecture Behavioral of SCCBMaster is

------------------------------------------------------------------------------------------------------------------
--  Bu adimda sistemin calisacagi durum makinesinin durumlari, giris ve cikis portlarina baglanacak sinyaller,
--  durumlar icin gerekli olacak counter ve busy bitleri gibi sinyaller olusturulmustur.
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
    
    -- signal      SSIODClock          :   std_logic                        :=    '0';   --  DEBUG AMACLIDIR!
    -- signal      SSIODClockPrev      :   std_logic;                                    --  DEBUG AMACLIDIR!
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
--  Bu adimda giris ve cikis portlari sinyallere yonlendirilmistir.
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
--  READY prosesi; eger yazma islemi bittiyse(SDone == '1') ve yazma durum makinesi baslangictaysa(SStateWriteBase == idle)
--  SReady sinyalini lojik-1 yapar. Ayrica sistem durdurulduysa(PIReset == '0') SReady sinyalini lojik-0 yapar.
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
--  Backend tarafina gelen baslatma sinyaline gore(SStart == '1') address, register ve data bilgilerini olusturulan register 
--  sinyallerine atar. Sistemin resetlenme durumuna gore bu sinyaller temizlenir.
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
--  CLKGEN prosesi; SCCB arayuzu icin gerekli olan REFERANS saat sinyallerini uretir. Bu noktada onemli olan durum sudur:
--  OV7670 datasheeti incelendiginde gonderilecek veriler SIOC cikisinin lojik-0 olduğu durumun tam ortasında degistirilir. 
--  Bu nedenden dolayi SIOC cikisi icin ek olarak bu cikisin yari periyoduna sahip ikincil bir saat sinyali uretilir.
--  
--  |¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______    =====>>>    SIOC Referans Saat
--              |               |               |               |               |
--              |               |               |               |               |
--  |¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_    =====>>>    DATA Referans Saat
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
--  DATA_WRITE prosesi; SCCB arayuzune uygun olarak yazma islemi yapacak olan durum makinesini icerir. Aktif 0 olarak ca-
--  lisan PIReset, aktif oldugu durumda butun islemleri, sayicilari, cikislari ve registerleri temizler.
-- 
--                                                              !!!!ONEMLI!!!!
--  SCCB arayuzu, idle durumundayken SIOD hattini yuksek empedans('Z'), SIOC hattini ise lojik-1 seviyesinde tutar. Baslangic kosulu,
--  SIOD hattini 'Z' durumundan lojik-1 durumuna getirir, ardindan SIOC hattini referans saatin yarı periyodu kadar bekledikten sonra
--  lojik-0 yaparak haberlesmeyi baslatir. Bitme kosulu ise, eger baska veri yazilmayacaksa ilk olarak SIOC'yi lojik-1, ardindan SIOD
--  hattini yarim periyot bekledikten sonra 'Z' yapar. Ancak baska veri yazilmaya devam edecek ise SIOD hattini 'Z' yerine lojik-1 yapar.
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
--  "idle" durumu; SStartReg tetiklendiginde address, register ve data bilgilerini registerlerden toplar ve SIOC referans
--  saatinin yukselen kenarinda "start_condition" durumuna gecer.
--  SStartReg'in tetiklenmedigi durumda sistem reset (SIOD = 'Z' - SIOC = '1') durumunda kalir.
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
--  "start_condition" durumu; 2 SIOC referans clock darbesinden sonra SIOD referansinin yukselen kenari ve SIOC referansinin
--  lojik-0 oldugu anda cache olarak alinan address verisinin ilk bitini sola 1 kere kaydirarak SIOD hattina yazar ve "send_addr" 
--  durumuna gecer.
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
--  "send_addr" durumu; SIOD referansinin yukselen kenari ve SIOC referansinin lojik-0 oldugu anda address verisinin geri kalanini
--  SIOD hattina yazar. Ardindan "Don't Care" bit durumuna gecer ve gecerken SIOD hattini lojik-0 tutar. 
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
--  "send_reg" durumu; SIOD referansinin yukselen kenari ve SIOC referansinin lojik-0 oldugu anda register verisini SIOD hattina yazar.
--  Ardindan "Don't Care" bit durumuna gecer ve gecerken SIOD hattini lojik-0 tutar. 
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
--  "reg_dc" durumu; "Don't Care" biti yazildiktan sonra diger durumlarda oldugu gibi SIOD ve SIOC referans saat sinyallerine
--  gore islem yapar. Bu sefer data verisinin ilk bitini sola kaydirarak SIOD hattina yazar ve "send_data" durumuna gecer.
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
--  "reg_dc" durumu; gonderilmek istenen verinin ilk biti yazdirildiktan sonra geri kalan bitler sola kaydirilarak SIOD hattina
--  yazilir. Ardindan "Don't Care" biti yazilir, 1 SIOD ve SIOC referans saati beklenir ve "data_dc" durumuna gecilir. 
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
------------------------------------------------------------------------------------------
--  "data_dc" durumu; sadece 1 clock SIOC referans bekleyerek "stop" durumuna gecer.
------------------------------------------------------------------------------------------
                when data_dc =>
                    if SSIOCClock = '1' and SSIOCClockPrev = '0' then
                        SData      <= (others => '0');
                        SStateWriteBase <= stop;
                    end if;
-------------------------------------------------------------------------------------------------------------------------------------------
--  "stop" durumu; ilk olarak SCCB haberlesmesini sonlandirmak icin ilk olarak SIOC hattini lojik-1 yapar, ardindan 1 SIOC saat
--  referansi bekledikten sonra SIOD hattini lojik-1 yapar ve "idle" durumuna gecis yapar.
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
