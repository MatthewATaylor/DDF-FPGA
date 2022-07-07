`timescale 1ns / 1ps

module disco_dance_floor_tb();
    logic clk = 0;
    
    logic eth_crsdv = 0;
    logic[1:0] eth_rxd = 0;
    logic eth_clk;
    
    logic[26:0] led;
    
    logic[0:1201] frame = 0;
    logic[10:0] frame_index = 1180;
    
    initial begin
        frame[0:63]      <= 64'b1010101010101010101010101010101010101010101010101010101010101011;  // Preamble
        frame[64:111]    <= 48'b111111111111111111111111111111111111111111111111;  // Dst MAC
        frame[112:159]   <= 48'b001010101111110100100110111010001011010000100001;  // Src MAC
        frame[160:175]   <= 16'b0001000000000000;  // EtherType
        // frame[176:191] is LED index (starts at 0)
        frame[192:839]   <= {648{1'b1}};  // Data
        frame[1000:1023] <= 24'b101010101010101010101010;  // Some random postfix bits
        // frame[1024:1200] is space between frames
    end
    
    always begin
        #5;
        clk <= ~clk;
    end
    
    always @ (posedge(eth_clk)) begin
        // Simulate Ethernet PHY
        
        // Data
        eth_rxd[0] <= frame[frame_index];
        eth_rxd[1] <= frame[frame_index + 1];
        
        // CRSDV control
        if (frame_index > 1023) begin
            eth_crsdv <= 0;
        end
        else begin
            eth_crsdv <= 1;
        end
        
        // Index bounds
        if (frame_index == 1200) begin
            frame_index <= 0;
            
            if (frame[176:191] == 439) begin
                frame[176:191] <= 0;
            end
            else begin
                frame[176:191] <= frame[176:191] + 1;
            end
        end
        else begin
            frame_index <= frame_index + 2;
        end
    end
    
    disco_dance_floor ddf(
        .clk(clk),
        .eth_crsdv(eth_crsdv),
        .eth_rxd(eth_rxd),
        .eth_clk(eth_clk),
        .led(led)
    );
endmodule
