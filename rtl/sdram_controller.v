/**
 * simple controller for ISSI IS42S16160G-7 SDRAM found in De0 Nano
 *  16Mbit x 16 data bit bus (32 megabytes)
 *  Default options
 *    100Mhz
 *    CAS 2
 *
 *  Very simple host interface
 *     * No burst support
 *     * haddr - address for reading and wriging 16 bits of data
 *     * data_input - data for writing, latched in when wr_enable is highz0
 *     * data_output - data for reading, comes available sometime *few clocks* after rd_enable and address is presented on bus
 *     * rst_n - start init ram process
 *     * rd_enable - read enable, on clk posedge haddr will be latched in, after *few clocks* data will be available on the data_output port
 *     * wr_enable - write enable, on clk posedge haddr and data_input will be latched in, after *few clocks* data will be written to sdram
 *
 * Theory
 *  This simple host interface expects you to know the timing and know
 *  how long to wait for init, write operations and read operations
 */

module sdram_controller (
    /* HOST INTERFACE */
    haddr, data_input, data_output, busy, rd_enable, wr_enable, rst_n, clk,

    /* SDRAM SIDE */
    addr, bank_addr, data, clock_enable, cs_n, ras_n, cas_n, we_n, data_mask_low, data_mask_high
);

/* Internal Parameters */
parameter ROW_WIDTH = 13;
parameter COL_WIDTH = 9;
parameter BANK_WIDTH = 2;

localparam SDRADDR_WIDTH = ROW_WIDTH > COL_WIDTH ? ROW_WIDTH : COL_WIDTH;
localparam HADDR_WIDTH = ROW_WIDTH + COL_WIDTH + BANK_WIDTH;
 
parameter CLK_FREQUENCY = 133;  // Mhz     
parameter REFRESH_TIME =  32;   // ms     (how often we need to refresh) 
parameter REFRESH_COUNT = 8192; // cycles (how many refreshes required per refresh time)

// clk / refresh =  clk / sec 
//                , sec / refbatch 
//                , ref / refbatch
localparam CYCLES_BETWEEN_REFRESH = ( CLK_FREQUENCY * 1_000 * REFRESH_TIME ) / REFRESH_COUNT;

// STATES - TOP LEVEL
localparam IDLE = 2'b00,
           INIT = 2'b01,
           REF =  2'b10;

// STATES - SUB LEVEL
localparam IDLE_IDLE = 3'b000;

localparam INIT_NOP1 = 3'b000,
           INIT_PRE1 = 3'b001,
           INIT_REF1 = 3'b010,
           INIT_NOP2 = 3'b011,
           INIT_REF2 = 3'b100,
           INIT_NOP3 = 3'b101,
           INIT_LOAD = 3'b110,
           INIT_NOP4 = 3'b111;

localparam REF_REF =  3'b000;
 
// Commands             CCRCWBBA
//                      ESSSE100
localparam CMD_PALL = 8'b10010001,
           CMD_REF  = 8'b10001000,
           CMD_NOP  = 8'b10111000,
           CMD_MRS  = 8'b10000000;

/* Interface Definition */
/* HOST INTERFACE */
input  [HADDR_WIDTH-1:0]   haddr;
input  [15:0]              data_input;
output [15:0]              data_output;
output                     busy;
input                      rd_enable;
input                      wr_enable;
input                      rst_n;
input                      clk;

/* SDRAM SIDE */
output [SDRADDR_WIDTH-1:0] addr;
output [BANK_WIDTH-1:0]    bank_addr;
inout  [15:0]              data;
output                     clock_enable;
output                     cs_n;
output                     ras_n;
output                     cas_n;
output                     we_n;
output                     data_mask_low;
output                     data_mask_high;

/* Internal Wiring */
reg [3:0] state_counter;
reg [8:0] refresh_counter;

reg [7:0] command;
reg [1:0] top_state;
reg [2:0] sub_state;

reg [7:0] next_command;
reg [3:0] next_wait;
reg [1:0] next_top;
reg [2:0] next_sub;



assign clock_enable = command[7];
assign cs_n         = command[6];
assign ras_n        = command[5];
assign cas_n        = command[4];
assign we_n         = command[3];
assign bank_addr[1:0] = command[2:1];
assign addr[10]     = command[0];

// Handle 
//   state counter 
//   state changes
//   and command output
always @ (posedge clk)
  if (~rst_n)
    begin
    top_state <= INIT;
    sub_state <= INIT_NOP1;
    command <= CMD_NOP;
    state_counter <= 4'hf;
    end
  else 
    begin
    top_state <= next_top;
    sub_state <= next_sub;
    command <= next_command;
    if (~state_counter)
      begin
      state_counter <= next_wait;
      end
    else
      begin
      state_counter <= state_counter - 1'b1;
      end
    end

// Handle refresh counter
always @ (posedge clk) 
 if (~rst_n) 
   refresh_counter <= 9'b0;
 else
   if (top_state == REF)
     refresh_counter <= 9'b0;
   else 
     refresh_counter <= refresh_counter + 1'b1;

// Next state logic
always @* 
begin
   case (top_state)
      IDLE:
        // Monitor for refresh
        begin
        if (refresh_counter >= CYCLES_BETWEEN_REFRESH)
          next_top <= REF;
        else 
          next_top <= top_state;
        
        next_sub <= IDLE_IDLE;
        next_wait <= 4'd0;
        next_command <= CMD_NOP; 
        end
      
      INIT:
        // Init SDRAM 
        if (~state_counter)
        case (sub_state)
          INIT_NOP1:
            begin
            next_top <= INIT;
            next_sub <= INIT_PRE1;
            next_wait <= 4'd2;
            next_command <= CMD_PALL;
            end
          INIT_PRE1:
            begin
            next_top <= INIT;
            next_sub <= INIT_REF1;
            next_wait <= 4'd1;
            next_command <= CMD_REF;
            end
          INIT_REF1:
            begin
            next_top <= INIT;
            next_sub <= INIT_NOP2;
            next_wait <= 4'd8;
            next_command <= CMD_NOP;
            end
          INIT_NOP2:
            begin
            next_top <= INIT;
            next_sub <= INIT_REF2;
            next_wait <= 4'd1;
            next_command <= CMD_REF;
            end
          INIT_REF2:
            begin
            next_top <= INIT;
            next_sub <= INIT_NOP3;
            next_wait <= 4'd8;
            next_command <= CMD_NOP;
            end
          INIT_NOP3:
            begin
            next_top <= INIT;
            next_sub <= INIT_LOAD;
            next_wait <= 4'd1;
            next_command <= CMD_MRS;            
            end
          INIT_LOAD:
            begin
            next_top <= INIT;
            next_sub <= INIT_NOP4;
            next_wait <= 4'd2;
            next_command <= CMD_NOP;  
            end
          INIT_NOP4:
            begin
            next_top <= IDLE;
            next_sub <= IDLE_IDLE;
            next_wait <= 4'd0;
            next_command <= CMD_NOP;
            end
          endcase
         else 
            begin
            // HOLD
            next_top <= top_state;
            next_sub <= sub_state;
            next_wait <= 4'd0;
            next_command <= command;
            end
      default:
        begin
        next_top <= top_state;
        next_sub <= sub_state;
        next_wait <= 4'd0;
        next_command <= command;
        end
   endcase
     

end

endmodule