module accumulator (
    clkIn,
    rstIn,
    dataIn,
    validIn,
    lastIn,
    dataOut,
    validOut);
    
    parameter FRAC_WIDTH    = 24;
    parameter EXP_WIDTH     =  8;
    
    localparam DATA_WIDTH   = FRAC_WIDTH + EXP_WIDTH;
    localparam ADD_LATENCY  = 13;
    localparam ID_WIDTH     = $clog2(ADD_LATENCY+1);
    localparam NUM_STAGES   = $clog2(ADD_LATENCY+1);
    localparam REG_WIDTH    = 2**ID_WIDTH;
    
    input clkIn;
    input rstIn;
    
    input [DATA_WIDTH-1:0] dataIn;
    input validIn;
    input lastIn;
    
    output [DATA_WIDTH-1:0] dataOut;
    output validOut;
    
    reg [ ID_WIDTH-1:0] idR;
    reg [REG_WIDTH-1:0] lastR;
    reg inSelR;
    
    reg [DATA_WIDTH-1:0] accumDataR;
    reg accumLastR;
    reg accumValidR;
    
    wire [DATA_WIDTH-1:0] accumData;
    wire accumValid;
    
    wire [ID_WIDTH-1:0] accumId;
    wire accumLast;
    
    always @(posedge clkIn) begin
        if (rstIn) begin
            idR     <= 0;
            lastR   <= 0;
        end else begin
            if (accumValid && accumLast) begin
                lastR[accumId]  <= 0;
            end
            if (validIn && lastIn) begin
                idR             <= idR + 1;
                lastR[idR]      <= 1;
            end    
        end
    end
    
    always @(posedge clkIn) begin
        if (rstIn) begin
            inSelR      <= 0;
            accumValidR <= 0;
        end else begin
            if (accumValid) begin
                if (lastR[accumId] | ((accumId == idR) && validIn && lastIn)) begin
                    inSelR      <= 0;
                    accumValidR <= 1;
                end else begin
                    inSelR      <= 1;
                    accumValidR <= 0;
                end
            end else begin
                inSelR      <= 0;
                accumValidR <= 0;
            end
        end
    end
    
    always @(posedge clkIn) begin
        accumDataR  <= accumData;
        accumLastR  <= accumLast;
    end
    
    wire [DATA_WIDTH-1:0] dataB;
    
    assign dataB = inSelR ? accumDataR : 0;
    
    floating_point_add #(.FRAC_WIDTH(FRAC_WIDTH), .EXP_WIDTH(EXP_WIDTH)) accum_i (
        .clkIn(clkIn),
        .rstIn(rstIn),
        .dataAIn(dataIn),
        .dataBIn(dataB),
        .validIn(validIn),
        .dataOut(accumData),
        .validOut(accumValid));        
        
    wire [ID_WIDTH:0] iDelay;
    wire [ID_WIDTH:0] oDelay;
    
    assign iDelay = {lastIn, idR};
    
    delay #(.DATA_WIDTH(ID_WIDTH+1), .LATENCY(ADD_LATENCY)) delay_i (
        .clkIn(clkIn),
        .rstIn(rstIn),
        .dataIn(iDelay),
        .dataOut(oDelay));
        
    assign accumLast = oDelay[ID_WIDTH];
    assign accumId   = oDelay[ID_WIDTH-1:0];
    
    wire [DATA_WIDTH-1:0] stageIData [0:NUM_STAGES-1];
    wire [DATA_WIDTH-1:0] stageOData [0:NUM_STAGES-1];
    
    wire stageIValid [0:NUM_STAGES-1];
    wire stageOValid [0:NUM_STAGES-1];
    
    wire stageILast  [0:NUM_STAGES-1];
    wire stageOLast  [0:NUM_STAGES-1];
    
    genvar i;
    generate
    
        for (i = 0; i < NUM_STAGES; i = i + 1) begin

            reg [DATA_WIDTH-1:0] dataR;
            reg validR;
            
            wire valid;
            
            wire [1:0] iDelay;
            wire [1:0] oDelay;
            
            if (i == 0) begin
                assign stageIData [i] = accumDataR;
                assign stageIValid[i] = accumValidR;
                assign stageILast [i] = accumLastR;
            end else begin
                assign stageIData [i] = stageOData [i-1];
                assign stageIValid[i] = stageOValid[i-1];
                assign stageILast [i] = stageOLast [i-1];
            end
                
            always @(posedge clkIn) begin
                if (rstIn) begin
                    validR <= 0;
                end else begin
                    if (stageIValid[i]) begin
                        if (validR | stageILast[i]) begin
                            validR  <= 0;
                        end else begin
                            validR  <= 1;
                        end
                    end
                end
            end
            
            assign valid = stageIValid[i] & (validR | stageILast[i]);
            
            always @(posedge clkIn) begin
                if (stageIValid[i]) begin
                    dataR   <= stageIData[i];
                end
            end
            
            wire [DATA_WIDTH-1:0] dataB;
            
            assign dataB = validR ? dataR  : 0;
                
            floating_point_add #(.FRAC_WIDTH(FRAC_WIDTH), .EXP_WIDTH(EXP_WIDTH)) add_i (
                .clkIn(clkIn),
                .rstIn(rstIn),
                .dataAIn(stageIData[i]),
                .dataBIn(dataB),
                .validIn(valid),
                .dataOut(stageOData[i]),
                .validOut(stageOValid[i]));
            
            delay #(.DATA_WIDTH(1), .LATENCY(ADD_LATENCY)) delay_i (
                .clkIn(clkIn),
                .rstIn(rstIn),
                .dataIn(stageILast[i]),
                .dataOut(stageOLast[i]));
        end
    endgenerate
    
    assign dataOut  = stageOData[NUM_STAGES-1];
    assign validOut = stageOLast[NUM_STAGES-1] & stageOValid[NUM_STAGES-1];
    
endmodule