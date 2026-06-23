// Measure the actual frequency response of the core_top audio low-pass, per K.
// Replicates the exact LPF block (aud_div/aud_acc/aud_lpf) and drives a tone,
// measuring output amplitude vs frequency so we can see what the K knob really does.
`timescale 1ns/1ps

module lpf #(parameter integer K = 1) (
    input              clk,
    input      [9:0]   pac_audio,
    output     [9:0]   out
);
    reg  [8:0]         aud_div = 9'd0;
    reg  [19:0]        aud_acc = 20'd0;
    reg  signed [18:0] aud_lpf = 19'd0;
    always @(posedge clk) begin
        aud_div <= aud_div + 9'd1;
        if (aud_div == 9'd511) begin
            aud_lpf <= aud_lpf + (($signed({1'b0, aud_acc[18:9], 8'd0}) - aud_lpf) >>> K);
            aud_acc <= pac_audio;
        end else begin
            aud_acc <= aud_acc + pac_audio;
        end
    end
    assign out = aud_lpf[17:8];
endmodule

module tb;
    reg clk = 0;
    always #20 clk = ~clk;          // 25 MHz; frame = 512*40ns = 48.8 kHz
    localparam real FS_IN = 25.0e6;

    reg [9:0] pac_audio = 10'd512;
    wire [9:0] o1, o2, o3;
    lpf #(1) u1 (clk, pac_audio, o1);
    lpf #(2) u2 (clk, pac_audio, o2);
    lpf #(3) u3 (clk, pac_audio, o3);

    real phase, pinc;
    integer i, n;
    integer mn1,mx1,mn2,mx2,mn3,mx3;
    real freqs [0:6];
    integer fi;

    initial begin
        freqs[0]=125; freqs[1]=250; freqs[2]=500; freqs[3]=1000;
        freqs[4]=2000; freqs[5]=4000; freqs[6]=8000;
        $display("  freq(Hz)   ampK1  ampK2  ampK3   (input amplitude = 400)");
        for (fi=0; fi<7; fi=fi+1) begin
            phase = 0.0;
            pinc  = 6.283185307*freqs[fi]/FS_IN;
            // settle ~30 ms, then measure ~10 ms
            mn1=2000;mx1=-2000;mn2=2000;mx2=-2000;mn3=2000;mx3=-2000;
            n = 1000000;           // ~40 ms of 25 MHz clocks
            for (i=0; i<n; i=i+1) begin
                @(posedge clk);
                pac_audio = 512 + $rtoi(400.0*$sin(phase));
                phase = phase + pinc;
                if (i > 750000) begin   // measure window (settled)
                    if ($signed({1'b0,o1}) < mn1) mn1=$signed({1'b0,o1});
                    if ($signed({1'b0,o1}) > mx1) mx1=$signed({1'b0,o1});
                    if ($signed({1'b0,o2}) < mn2) mn2=$signed({1'b0,o2});
                    if ($signed({1'b0,o2}) > mx2) mx2=$signed({1'b0,o2});
                    if ($signed({1'b0,o3}) < mn3) mn3=$signed({1'b0,o3});
                    if ($signed({1'b0,o3}) > mx3) mx3=$signed({1'b0,o3});
                end
            end
            $display("  %8.0f   %5d  %5d  %5d", freqs[fi],
                     (mx1-mn1)/2, (mx2-mn2)/2, (mx3-mn3)/2);
        end
        $finish;
    end
endmodule
