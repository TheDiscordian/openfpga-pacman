// Does the audio resampler alias HF content into the audible band (the "harsh buzz
// around the sound")? Compare the CURRENT chain (box-average -> decimate to 48k ->
// IIR@48k) against a PROPOSED chain (IIR@clk_sys BEFORE decimation -> point-sample
// to 48k). Sweep tone frequency incl. above the 48k Nyquist; measure the baseband
// output swing each chain produces. A good anti-alias passes lows, kills HF folds.
`timescale 1ns/1ps

module tb;
    reg clk = 0;
    always #20 clk = ~clk;              // 25 MHz ~= clk_sys; 48.8 kHz frame = 512 clks
    localparam real FS = 25.0e6;

    reg [9:0] pac_audio = 10'd512;

    // ---- CURRENT: box-average over 512, then IIR@48k with K=3 ----
    localparam integer K = 3;
    reg  [8:0]         cdiv = 0;
    reg  [19:0]        cacc = 0;
    reg  signed [18:0] clpf = 0;
    always @(posedge clk) begin
        cdiv <= cdiv + 9'd1;
        if (cdiv == 9'd511) begin
            clpf <= clpf + (($signed({1'b0, cacc[18:9], 8'd0}) - clpf) >>> K);
            cacc <= pac_audio;
        end else cacc <= cacc + pac_audio;
    end
    wire [9:0] cur_out = clpf[17:8];

    // ---- PROPOSED: IIR at clk_sys (pre-decimation anti-alias), KP=9 (~7.6 kHz),
    // then point-sample into the 48k frame ----
    localparam integer KP = 9;
    reg  signed [18:0] plpf = 0;       // 10.8 fixed, runs every clk
    reg  [8:0]         pdiv = 0;
    reg  [9:0]         prop_out = 0;
    always @(posedge clk) begin
        plpf <= plpf + (($signed({1'b0, pac_audio, 8'd0}) - plpf) >>> KP);
        pdiv <= pdiv + 9'd1;
        if (pdiv == 9'd511) prop_out <= plpf[17:8];   // decimate to 48 kHz
    end

    real phase, pinc;
    integer i, n;
    integer cmn,cmx,pmn,pmx;
    real freqs [0:8];
    integer fi;

    initial begin
        freqs[0]=500;  freqs[1]=2000;  freqs[2]=8000;  freqs[3]=15000;
        freqs[4]=24000; freqs[5]=30000; freqs[6]=48000; freqs[7]=60000; freqs[8]=90000;
        $display(" tone(Hz)  CURRENT  PROPOSED   (in=400; >24kHz should be killed)");
        for (fi=0; fi<9; fi=fi+1) begin
            phase=0.0; pinc=6.283185307*freqs[fi]/FS;
            cmn=2000;cmx=-2000;pmn=2000;pmx=-2000;
            n=1500000;
            for (i=0;i<n;i=i+1) begin
                @(posedge clk);
                pac_audio = 512 + $rtoi(400.0*$sin(phase));
                phase = phase + pinc;
                if (i>1100000) begin
                    if ($signed({1'b0,cur_out})<cmn)  cmn=$signed({1'b0,cur_out});
                    if ($signed({1'b0,cur_out})>cmx)  cmx=$signed({1'b0,cur_out});
                    if ($signed({1'b0,prop_out})<pmn) pmn=$signed({1'b0,prop_out});
                    if ($signed({1'b0,prop_out})>pmx) pmx=$signed({1'b0,prop_out});
                end
            end
            $display(" %8.0f   %5d    %5d", freqs[fi], (cmx-cmn)/2, (pmx-pmn)/2);
        end
        $finish;
    end
endmodule
