library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

use STD.textio.all;
use work.pJoypad.all;

entity joypad is
   port 
   (
      clk1x                : in  std_logic;
      clk2x                : in  std_logic;
      clk2xIndex           : in  std_logic;
      ce                   : in  std_logic;
      reset                : in  std_logic;

      isPal                : in  std_logic; -- passed through for GunCon
      
      joypad1              : in  joypad_t;
      joypad2              : in  joypad_t;
      
      memcard1_available   : in  std_logic;
      memcard2_available   : in  std_logic;
      
      rumbleOn             : out std_logic := '0';
      
      irqRequest           : out std_logic := '0';
      
      MouseEvent           : in  std_logic;
      MouseLeft            : in  std_logic;
      MouseRight           : in  std_logic;
      MouseX               : in  signed(8 downto 0);
      MouseY               : in  signed(8 downto 0);
      Gun1X                : in  unsigned(7 downto 0);
      Gun2X                : in  unsigned(7 downto 0);
      Gun1Y_scanlines      : in  unsigned(8 downto 0);
      Gun2Y_scanlines      : in  unsigned(8 downto 0);
      Gun1AimOffscreen     : in  std_logic;
      Gun2AimOffscreen     : in  std_logic;

      mem1_request         : out std_logic;
      mem1_BURSTCNT        : out std_logic_vector(7 downto 0) := (others => '0'); 
      mem1_ADDR            : out std_logic_vector(19 downto 0) := (others => '0');                       
      mem1_DIN             : out std_logic_vector(63 downto 0) := (others => '0');
      mem1_BE              : out std_logic_vector(7 downto 0) := (others => '0'); 
      mem1_WE              : out std_logic;
      mem1_RD              : out std_logic;
      mem1_ack             : in  std_logic;      
      
      mem2_request         : out std_logic;
      mem2_BURSTCNT        : out std_logic_vector(7 downto 0) := (others => '0'); 
      mem2_ADDR            : out std_logic_vector(19 downto 0) := (others => '0');                       
      mem2_DIN             : out std_logic_vector(63 downto 0) := (others => '0');
      mem2_BE              : out std_logic_vector(7 downto 0) := (others => '0'); 
      mem2_WE              : out std_logic;
      mem2_RD              : out std_logic;
      mem2_ack             : in  std_logic;
      
      mem_DOUT             : in  std_logic_vector(63 downto 0);
      mem_DOUT_READY       : in  std_logic;      
      
      bus_addr             : in  unsigned(3 downto 0); 
      bus_dataWrite        : in  std_logic_vector(31 downto 0);
      bus_read             : in  std_logic;
      bus_write            : in  std_logic;
      bus_writeMask        : in  std_logic_vector(3 downto 0);
      bus_dataRead         : out std_logic_vector(31 downto 0);
                           
      SS_reset             : in  std_logic;
      SS_DataWrite         : in  std_logic_vector(31 downto 0);
      SS_Adr               : in  unsigned(2 downto 0);
      SS_wren              : in  std_logic;
      SS_rden              : in  std_logic;
      SS_DataRead          : out std_logic_vector(31 downto 0);
      SS_idle              : out std_logic
   );
end entity;

architecture arch of joypad is

   signal receiveFilled       : std_logic;
      
   signal JOY_STAT            : std_logic_vector(31 downto 0);
   signal JOY_STAT_ACK        : std_logic;
   signal transmitFilled      : std_logic;
   signal transmitBuffer      : std_logic_vector(7 downto 0);
   signal transmitValue       : std_logic_vector(7 downto 0);
      
   signal transmitting        : std_logic;
   signal waitAck             : std_logic;
      
   signal baudCnt             : unsigned(20 downto 0) := (others => '0');
      
   signal JOY_MODE            : std_logic_vector(15 downto 0);
   signal JOY_CTRL            : std_logic_vector(15 downto 0);
   signal JOY_BAUD            : std_logic_vector(15 downto 0);
   signal JOY_CTRL_13_1       : std_logic;
      
   signal beginTransfer       : std_logic := '0';
   signal actionNext          : std_logic := '0';
   signal actionNextPad       : std_logic := '0';
      
   -- devices  
   signal isActivePad         : std_logic;
   signal isActiveMem1        : std_logic;
   signal isActiveMem2        : std_logic;
      
   signal selectedPort1       : std_logic;
   signal selectedPort2       : std_logic;
   signal selectedPort        : std_logic;
      
   signal ack                 : std_logic;
   signal ackPad              : std_logic;
   signal ackMem1             : std_logic;
   signal ackMem2             : std_logic;
   
   signal receiveBuffer       : std_logic_vector(7 downto 0);
   signal receiveBufferPad    : std_logic_vector(7 downto 0);
   signal receiveBufferMem1   : std_logic_vector(7 downto 0);
   signal receiveBufferMem2   : std_logic_vector(7 downto 0);
   
   signal receiveValid        : std_logic;
   signal receiveValidPad     : std_logic;
   signal receiveValidMem1    : std_logic;
   signal receiveValidMem2    : std_logic;

   signal joypad_selected     : joypad_t;
   signal GunX                : unsigned(7 downto 0);
   signal GunY_scanlines      : unsigned(8 downto 0);
   signal GunAimOffscreen     : std_logic;

   -- savestates
   type t_ssarray is array(0 to 7) of std_logic_vector(31 downto 0);
   signal ss_in  : t_ssarray := (others => (others => '0'));  
   signal ss_out : t_ssarray := (others => (others => '0'));  
  
begin 

   JOY_STAT( 0) <= not transmitFilled;
   JOY_STAT( 1) <= receiveFilled;
   JOY_STAT( 2) <= (not transmitFilled) and (not transmitting);
   JOY_STAT( 3) <= '0'; -- RX parity error
   JOY_STAT( 4) <= '0'; -- unknown
   JOY_STAT( 5) <= '0'; -- unknown
   JOY_STAT( 6) <= '0'; -- unknown
   JOY_STAT( 7) <= JOY_STAT_ACK;
   JOY_STAT( 8) <= '0'; -- unknown
   JOY_STAT( 9) <= irqRequest;
   JOY_STAT(10) <= '0'; -- unknown
   JOY_STAT(31 downto 11) <= (others => '0'); --std_logic_vector(baudCnt); ??

   ss_out(0)(20 downto 0)  <= std_logic_vector(baudCnt);  
   ss_out(1)(15 downto 0)  <= JOY_STAT(15 downto 0);    
   ss_out(1)(31 downto 16) <= JOY_MODE; 
   ss_out(2)(15 downto  0) <= JOY_CTRL;      
   ss_out(2)(31 downto 16) <= JOY_BAUD;   
   ss_out(3)( 7 downto  0) <= transmitBuffer;
   ss_out(3)(15 downto  8) <= transmitValue;
   ss_out(3)(23 downto 16) <= receiveBuffer;   
   --ss_out(3)(31 downto 24) <= std_logic_vector(to_unsigned(activeDevice, 8));    
   --ss_out(4)(15 downto 8)  <= std_logic_vector(to_unsigned(tcontrollerState'POS(controllerState), 8));       
   ss_out(4)(19)           <= receiveFilled; 
   ss_out(4)(16)           <= transmitFilled;
   ss_out(4)(17)           <= transmitting;  
   ss_out(4)(18)           <= waitAck;        

   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         if (reset = '1') then
         
            baudCnt         <= unsigned(ss_in(0)(20 downto 0));
            irqRequest      <= ss_in(1)(9);
            receiveFilled   <= ss_in(4)(19);
            JOY_STAT_ACK    <= ss_in(1)(7);
            transmitFilled  <= ss_in(4)(16);
            transmitting    <= ss_in(4)(17);
            waitAck         <= ss_in(4)(18);
            JOY_MODE        <= ss_in(1)(31 downto 16);
            JOY_CTRL        <= ss_in(2)(15 downto  0);
            JOY_BAUD        <= ss_in(2)(31 downto 16);
            
            transmitBuffer  <= ss_in(3)(7 downto 0);
            transmitValue   <= ss_in(3)(15 downto 8);
            receiveBuffer   <= ss_in(3)(23 downto 16);
            --activeDevice    <= to_integer(unsigned(ss_in(3)(31 downto 24)));
            --controllerState <= tcontrollerState'VAL(to_integer(unsigned(ss_in(4)(15 downto 8))));
            
            beginTransfer   <= '0';
            actionNext      <= '0';

         elsif (ce = '1') then
         
            bus_dataRead <= (others => '0');

            beginTransfer <= '0';

            -- bus read
            if (bus_read = '1') then
               case (bus_addr(3 downto 0)) is
                  when x"0" =>
                     if (receiveFilled = '1') then
                        receiveFilled <= '0';
                        bus_dataRead  <= receiveBuffer & receiveBuffer & receiveBuffer & receiveBuffer;
                     else
                        bus_dataRead  <= (others => '1');
                     end if;
                     
                  when x"4" =>
                     bus_dataRead <= JOY_STAT;
                     JOY_STAT_ACK <= '0';
                     
                  when x"8" =>
                     bus_dataRead <= x"0000" & JOY_MODE;
                     
                  when x"A" =>
                     bus_dataRead <= x"0000" & JOY_CTRL;                  
                     
                  when x"E" =>
                     bus_dataRead <= x"0000" & JOY_BAUD;
                     
                  when others => 
                     bus_dataRead <= x"0000CBAD";
               end case;
            end if;

            -- bus write
            if (bus_write = '1') then
               case (bus_addr(3 downto 0)) is
                  when x"0" =>
                     transmitFilled <= '1';
                     transmitBuffer <= bus_dataWrite(7 downto 0);
                     if (transmitting = '0' and waitAck = '0' and JOY_CTRL(1 downto 0) = "11") then
                        beginTransfer <= '1';
                     end if;
                     
                  when x"8" =>
                     if (bus_writeMask(1 downto 0) /= "00") then
                        JOY_MODE <= bus_dataWrite(15 downto 0);
                     elsif (bus_writeMask(3 downto 2) /= "00") then
                        JOY_CTRL <= bus_dataWrite(31 downto 16);
                        
                        if (bus_dataWrite(22) = '1') then -- reset
                           transmitFilled  <= '0';
                           transmitting    <= '0';
                           receiveFilled   <= '0';
                           irqRequest      <= '0';
                           JOY_STAT_ACK    <= '0';
                           JOY_CTRL        <= (others => '0');
                           JOY_MODE        <= (others => '0');
                        else
                           if (bus_dataWrite(20) = '1') then -- ack
                              irqRequest <= '0';                           
                           end if;
                           
                           if (bus_dataWrite(17 downto 16) = "11") then -- select and tx en
                              if (transmitting = '0' and waitAck = '0' and transmitFilled = '1') then
                                 beginTransfer <= '1';
                              end if;
                           else
                              baudCnt         <= (others => '0');
                              transmitting    <= '0';
                              waitAck         <= '0';
                           end if;
                        end if; 
                     end if;
                     
                  when x"C" =>
                     if (bus_writeMask(3 downto 2) /= "00") then
                        JOY_BAUD <= bus_dataWrite(31 downto 16);
                     end if;
                  
                  when others => null;
               end case;
            end if;
            
            actionNext    <= '0';
            actionNextPad <= '0';
            if (baudCnt > 0) then
               baudCnt <= baudCnt - 1;
               if (baudCnt = 3) then
                  actionNextPad <= '1';
               end if;
               if (baudCnt = 2) then
                  actionNext <= '1';
               end if;
            end if;

            if (beginTransfer = '1') then
               JOY_CTRL(2)    <= '1';
               transmitValue  <= transmitBuffer;
               transmitFilled <= '0';
               transmitting   <= '1';
               baudCnt        <= to_unsigned(to_integer(unsigned(JOY_BAUD)) * 8, 21);
               if (unsigned(JOY_BAUD) = 0) then
                  baudCnt     <= to_unsigned(8, 21);
               end if;
            elsif (actionNext = '1') then
               if (transmitting = '1') then
                  JOY_CTRL(2)    <= '1';
                  if (receiveValid = '1') then
                     receiveBuffer <= receiveBufferPad or receiveBufferMem1 or receiveBufferMem2;
                  else
                     receiveBuffer  <= x"FF";
                  end if;
                  receiveFilled  <= '1';
                  transmitting   <= '0';
                  if (ack = '1') then
                     waitAck <= '1';
                     if (ackMem1 = '1') then
                        baudCnt <= to_unsigned(1502, 21);
                     else
                        baudCnt <= to_unsigned(452, 21);
                     end if;
                  end if;
               elsif (waitAck = '1') then
                  JOY_STAT_ACK <= '1';
                  if (JOY_CTRL(12) = '1') then -- irq ena
                     irqRequest <= '1';
                  end if;
                  waitAck <= '0';
                  if (transmitFilled = '1' and JOY_CTRL(1 downto 0) = "11") then
                     beginTransfer <= '1';
                  end if;
               end if;
            end if;
            
            JOY_CTRL_13_1 <= JOY_CTRL(13);
         end if;
      end if;
   end process;
   
   ack          <= ackPad or ackMem1 or ackMem2;
   receiveValid <= receiveValidPad or receiveValidMem1 or receiveValidMem2;
   
   selectedPort1 <= '1' when (JOY_CTRL(13) = '0' and JOY_CTRL(1 downto 0) = "11") else '0';
   selectedPort2 <= '1' when (JOY_CTRL(13) = '1' and JOY_CTRL(1 downto 0) = "11") else '0';
   selectedPort  <= '1' when (JOY_CTRL(13) = JOY_CTRL_13_1 and JOY_CTRL(1 downto 0) = "11") else '0';

   joypad_selected <= joypad2 when selectedPort2 else joypad1;
   GunX            <= Gun2X when selectedPort2 else Gun1X;
   GunY_scanlines  <= Gun2Y_scanlines when selectedPort2 else Gun1Y_scanlines;
   GunAimOffscreen <= Gun2AimOffscreen when selectedPort2 else Gun1AimOffscreen;

   ijoypad_pad : entity work.joypad_pad
   port map
   (
      clk1x                => clk1x,    
      ce                   => ce,       
      reset                => reset,    
       
      joypad               => joypad_selected,
      isPal                => isPal,

      selected             => selectedPort,
      actionNext           => actionNextPad,
      transmitting         => transmitting,
      transmitValue        => transmitValue,
 
      isActive             => isActivePad,
      slotIdle             => not (isActiveMem1 or isActiveMem2),

      receiveValid         => receiveValidPad,
      receiveBuffer        => receiveBufferPad,
      ack                  => ackPad,

      rumbleOn             => rumbleOn,

      MouseEvent           => MouseEvent,
      MouseLeft            => MouseLeft,
      MouseRight           => MouseRight,
      MouseX               => MouseX,
      MouseY               => MouseY,
      GunX                 => GunX,
      GunY_scanlines       => GunY_scanlines,
      GunAimOffscreen      => GunAimOffscreen
   );
   
   ijoypad_mem1 : entity work.joypad_mem
   port map
   (
      clk1x                => clk1x, 
      clk2x                => clk2x,
      clk2xIndex           => clk2xIndex,      
      ce                   => ce,       
      reset                => reset,    
       
      memcard_available    => memcard1_available,
      mem_request          => mem1_request,   
      mem_BURSTCNT         => mem1_BURSTCNT,  
      mem_ADDR             => mem1_ADDR,      
      mem_DIN              => mem1_DIN,       
      mem_BE               => mem1_BE,        
      mem_WE               => mem1_WE,        
      mem_RD               => mem1_RD,       
      mem_ack              => mem1_ack,       
      mem_DOUT             => mem_DOUT,      
      mem_DOUT_READY       => mem_DOUT_READY,
      
      selected             => selectedPort1,
      actionNext           => actionNextPad,
      transmitting         => transmitting,
      transmitValue        => transmitValue,
      
      isActive             => isActiveMem1,
      slotIdle             => not isActivePad,
      
      receiveValid         => receiveValidMem1,
      receiveBuffer        => receiveBufferMem1,
      ack                  => ackMem1
   );
   
   ijoypad_mem2 : entity work.joypad_mem
   port map
   (
      clk1x                => clk1x, 
      clk2x                => clk2x,
      clk2xIndex           => clk2xIndex,      
      ce                   => ce,       
      reset                => reset,    
      
      memcard_available    => memcard2_available,
      mem_request          => mem2_request,   
      mem_BURSTCNT         => mem2_BURSTCNT,  
      mem_ADDR             => mem2_ADDR,      
      mem_DIN              => mem2_DIN,       
      mem_BE               => mem2_BE,        
      mem_WE               => mem2_WE,        
      mem_RD               => mem2_RD,       
      mem_ack              => mem2_ack,       
      mem_DOUT             => mem_DOUT,      
      mem_DOUT_READY       => mem_DOUT_READY,
      
      selected             => selectedPort2,
      actionNext           => actionNextPad,
      transmitting         => transmitting,
      transmitValue        => transmitValue,
      
      isActive             => isActiveMem2,
      slotIdle             => not isActivePad,
      
      receiveValid         => receiveValidMem2,
      receiveBuffer        => receiveBufferMem2,
      ack                  => ackMem2
   );
   
--##############################################################
--############################### savestates
--##############################################################

   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
      
         if (SS_reset = '1') then
         
            for i in 0 to 1 loop
               ss_in(i) <= (others => '0');
            end loop;
            
         elsif (SS_wren = '1') then
            ss_in(to_integer(SS_Adr)) <= SS_DataWrite;
         end if;
         
         SS_idle <= '0';
         if (transmitting = '0' and waitAck = '0' and beginTransfer = '0' and actionNext = '0' and isActivePad = '0') then
            SS_idle <= '1';
         end if;
         
         if (SS_rden = '1') then
            SS_DataRead <= ss_out(to_integer(SS_Adr));
         end if;
      
      end if;
   end process;
   
   -- synthesis translate_off

   goutput : if 1 = 1 generate
   signal outputCnt : unsigned(31 downto 0) := (others => '0'); 
   
   begin
      process
         constant WRITETIME            : std_logic := '1';
         
         file outfile                  : text;
         variable f_status             : FILE_OPEN_STATUS;
         variable line_out             : line;
            
         variable clkCounter           : unsigned(31 downto 0);
         variable newoutputCnt         : unsigned(31 downto 0);
            
         variable bus_adr              : unsigned(7 downto 0);
         variable bus_data             : unsigned(15 downto 0);
         variable transmit_1           : std_logic;
         variable irq_1                : std_logic;
         variable bus_read_1           : std_logic;
         variable bus_addr_1           : unsigned(3 downto 0); 
      begin
   
         file_open(f_status, outfile, "R:\\debug_pad_sim.txt", write_mode);
         file_close(outfile);
         file_open(f_status, outfile, "R:\\debug_pad_sim.txt", append_mode);
         
         while (true) loop
            
            wait until rising_edge(clk1x);
            
            if (reset = '1') then
               clkCounter := (others => '0');
            end if;
            
            newoutputCnt := outputCnt;
            
            if (bus_write = '1') then
               write(line_out, string'("WRITE: "));
               if (WRITETIME = '1') then
                  write(line_out, to_hstring(clkCounter));
                  write(line_out, string'(" ")); 
               end if;
               bus_adr  := x"0" & bus_addr;
               bus_data := unsigned(bus_dataWrite(15 downto 0));
               if (bus_addr = x"8" and bus_writeMask(3 downto 2) /= "00") then
                  bus_adr := x"0A";
                  bus_data := unsigned(bus_dataWrite(31 downto 16));
               end if;
               if (bus_addr = x"C" and bus_writeMask(3 downto 2) /= "00") then
                  bus_adr := x"0E";
                  bus_data := unsigned(bus_dataWrite(31 downto 16));
               end if;
               write(line_out, to_hstring(bus_adr));
               write(line_out, string'(" ")); 
               write(line_out, to_hstring(bus_data));
               writeline(outfile, line_out);
               newoutputCnt := newoutputCnt + 1;
            end if; 
            
            if (bus_read_1 = '1') then
               write(line_out, string'("READ: "));
               if (WRITETIME = '1') then
                  write(line_out, to_hstring(clkCounter));
               end if;
               write(line_out, string'(" 0")); 
               write(line_out, to_hstring(bus_addr_1));
               write(line_out, string'(" ")); 
               write(line_out, to_hstring(bus_dataRead(15 downto 0)));
               writeline(outfile, line_out);
               newoutputCnt := newoutputCnt + 1;
            end if; 
            bus_read_1 := bus_read;
            bus_addr_1 := bus_addr;
            
            if (beginTransfer = '1') then
               write(line_out, string'("BEGINTRANSFER: "));
               if (WRITETIME = '1') then
                  write(line_out, to_hstring(clkCounter - 1));
               end if;
               write(line_out, string'(" 00 00")); 
               write(line_out, to_hstring(transmitBuffer));
               writeline(outfile, line_out);
               newoutputCnt := newoutputCnt + 1;
            end if;             
            
            if (transmit_1 = '1') then
               write(line_out, string'("TRANSMIT: "));
               if (WRITETIME = '1') then
                  write(line_out, to_hstring(clkCounter + 1));
               end if;
               write(line_out, string'(" 00 00")); 
               write(line_out, to_hstring(receiveBuffer));
               writeline(outfile, line_out);
               newoutputCnt := newoutputCnt + 1;
            end if; 
            transmit_1 := (not beginTransfer) and actionNext and transmitting;
            
            if (irq_1 = '1') then
               write(line_out, string'("IRQ: "));
               if (WRITETIME = '1') then
                  write(line_out, to_hstring(clkCounter));
               end if;
               write(line_out, string'(" 00 ")); 
               write(line_out, to_hstring(JOY_STAT(15 downto 0)));
               writeline(outfile, line_out);
               newoutputCnt := newoutputCnt + 1;
            end if; 
            irq_1 := (not beginTransfer) and actionNext and (not transmitting) and JOY_CTRL(12);
            
            outputCnt <= newoutputCnt;
            clkCounter := clkCounter + 1;
           
         end loop;
         
      end process;
   
   end generate goutput;
   
   -- synthesis translate_on
end architecture;





