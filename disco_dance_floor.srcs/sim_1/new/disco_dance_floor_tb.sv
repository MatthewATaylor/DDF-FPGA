`timescale 1ns / 1ps

module disco_dance_floor_tb();
    logic clk = 0;
    
    logic eth_crsdv = 0;
    logic[1:0] eth_rxd = 0;
    logic eth_clk;
    
    logic[26:0] led;
    
    logic[1201:0] frame = 0;
    logic[10:0] frame_index = 1180;
    
    logic[9:0] led_index;
    
    assign led_index = frame[191:176];
    
    initial begin
        frame[63:0]      <= 64'b1101010101010101010101010101010101010101010101010101010101010101;  // Preamble
        frame[111:64]    <= 48'b111111111111111111111111111111111111111111111111;  // Dst MAC
        frame[159:112]   <= 48'b001010101111110100100110111010001011010000100001;  // Src MAC
        frame[175:160]   <= 16'b0000000000001000;  // EtherType
        frame[191:176]   <= 439;  // LED index
        frame[839:192]   <= {648{1'b1}};  // Data
        frame[1023:1000] <= 24'b101010101010101010101010;  // Some random postfix bits
        // frame[1024:1201] is space between frames
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
            
            if (frame[191:176] == 439) begin
                frame[191:176] <= 0;
            end
            else begin
                frame[191:176] <= frame[191:176] + 1;
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
