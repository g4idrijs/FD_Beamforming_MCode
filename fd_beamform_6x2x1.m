%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% wl_example_8x2_array.m
%
% Compatibility:
%   WARPLab:    v7.1.0 and later
%   Hardware:   v2 and v3
%
% Description:
%   See warpproject.org/trac/wiki/WARPLab/Examples/8x2Array
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
clear;
close all;

USE_AGC = true;
RUN_CONTINOUSLY = false ;
numPkts = 1;

PAYLOAD_LENGTH = 2.^ 12; % max is 2^15

TXRX_DELAY = 41;

SHORT_SYMS_REPETITIONS =  4*30% default is 30

NUM_PREAMBLE_SAMPLES_LNA_SETTLE = 300;

numTxAntennas = 6;
numUsers = 1;
numRxAntennas = 2;

% choose the length of the pilot signal. Longer 
% pilots lead to better estimation accuracy but more overhead.
pilotLength = 128; % length of per-antenna pilot symbol in samples

% Pilot tone frequency. 
% The pilot will be a tone at a given frequency. %
% the frequency should be the center frequency around which communication will occur. 
pilotToneFrequency = 1.25e6;

payloadToneFreq = 1.25e6;

% Choose the length of the guard interval between pilots from each antenna. 
% This may not be necessary, but it does greatly aid in the visualization of 
% the orthogonal pilots
guardIntervalLength = 256;

payloadAmplitude = 0.9;

pilotAmplitude = 0.9;



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Set up the WARPLab experiment
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


experiment = fd_beamform_wl_control(...
    numTxAntennas, numRxAntennas,numUsers);

experiment.set(...
    'USE_WARPLAB_TXRX', true, ...
    'MODEL_NOISE', true, ...
    'MODEL_DELAY', true, ...
    'snr_dB', 100, ...
    'delay', TXRX_DELAY);


if experiment.USE_WARPLAB_TXRX == true

    %Create a vector of node objects
    %This experiment uses 3 nodes: 2 will act as a transmitter and 1 will act
    %as a receiver.
    %   nodes(0): Primary transmitter
    %   nodes(1): Secondary transmitter (receives clocks and triggers from
    %             primary transmittter)
    %   nodes(3): Receiver
    nodes = wl_initNodes(3);


    bs = commNode(nodes(1:2));

    user = commNode(nodes(3));

    %Create a UDP broadcast trigger and tell each node to be ready for it
    experiment.eth_trig = wl_trigger_eth_udp_broadcast;
    wl_triggerManagerCmd(nodes,'add_ethernet_trigger',[experiment.eth_trig]);

    %Read Trigger IDs into workspace
    [T_IN_ETH,T_IN_ENERGY,T_IN_AGCDONE,T_IN_REG,T_IN_D0,T_IN_D1,T_IN_D2,T_IN_D3] =  wl_getTriggerInputIDs(nodes(1));
    [T_OUT_BASEBAND, T_OUT_AGC, T_OUT_D0, T_OUT_D1, T_OUT_D2, T_OUT_D3] = wl_getTriggerOutputIDs(nodes(1));

    %For the primary transmit node, we will allow Ethernet to trigger the buffer
    %baseband, the AGC, and debug0 (which is mapped to pin 8 on the debug
    %header). We also will allow Ethernet to trigger the same signals for the 
    %receiving node.
    % wl_triggerManagerCmd([nodes(1), nodes(3)],'output_config_input_selection', ...
    %     [T_OUT_BASEBAND,T_OUT_AGC,T_OUT_D0, T_OUT_D1],[T_IN_ETH,T_IN_REG]);
    wl_triggerManagerCmd([nodes(1)],'output_config_input_selection', ...
        [T_OUT_BASEBAND,T_OUT_AGC,T_OUT_D0, T_OUT_D1],[T_IN_ETH,T_IN_REG]);


    %For the secondary transmit node, we will allow debug3 (mapped to pin 15 on the
    %debug header) to trigger the buffer baseband, and the AGC
    wl_triggerManagerCmd(nodes(2),'output_config_input_selection', ...
        [T_OUT_BASEBAND,T_OUT_AGC],[T_IN_D3]);

    wl_triggerManagerCmd([nodes(3)],'output_config_input_selection', ...
        [T_OUT_BASEBAND,T_OUT_AGC],[T_IN_D3]);

    %For the secondary node, we enable the debounce circuity on the debug 3 input
    %to deal with the fact that the signal may be noisy.
    wl_triggerManagerCmd(nodes(2), 'input_config_debounce_mode',[T_IN_D3],'enable'); 

    %Since the debounce circuitry is enabled, there will be a delay at the
    %receiver node for its input trigger. To better align the transmitter and
    %receiver, we can artificially delay the transmitters trigger outputs that
    %drive the buffer baseband and the AGC.
    %
    %NOTE:  Due to HW changes in WARPLab 7.2.0, the input delay of the trigger 
    %manager increased by one clock cycle;  Therefore, when using WARPLab 7.2.0, 
    %we need to increase the output delay by one step.  If using WARPLab 7.1.0, 
    %please use the commented out line below:
    %
    %nodes(1).wl_triggerManagerCmd('output_config_delay',[T_OUT_BASEBAND,T_OUT_AGC],[50]); %50ns delay  - WARPLab 7.1.0
    %1
    nodes(1).wl_triggerManagerCmd('output_config_delay',[T_OUT_BASEBAND,T_OUT_AGC],[56.25]); %56.25ns delay  - WARPLab 7.2.0

    %Get IDs for the interfaces on the boards. Since this example assumes each
    %board has the same interface capabilities, we only need to get the IDs
    %from one of the boards
    [RFA,RFB,RFC,RFD] = wl_getInterfaceIDs(nodes(1));

    %Set up the interface for the experiment
    wl_interfaceCmd(nodes,'RF_ALL','tx_gains',2,20);
    wl_interfaceCmd(nodes,'RF_ALL','channel',2.4,11);



    wl_interfaceCmd(nodes,'RF_ALL','tx_lpf_corn_freq',2); %Configure Tx for 36MHz of bandwidth
    wl_interfaceCmd(nodes,'RF_ALL','rx_lpf_corn_freq',3); %Configure Rx for 36MHz of bandwidth

    %We'll use the transmitter's I/Q buffer size to determine how long our
    %transmission can be
    txLength = nodes(1).baseband.txIQLen;

    %Set up the baseband for the experiment
    wl_basebandCmd(nodes,'tx_delay',0);
    wl_basebandCmd(nodes,'tx_length',txLength);

    Ts = 1/(wl_basebandCmd(nodes(1),'tx_buff_clk_freq'));


    if(USE_AGC)
        wl_interfaceCmd(nodes,'RF_ALL','rx_gain_mode','automatic');
        wl_basebandCmd(nodes,'agc_target',-8);
        wl_basebandCmd(nodes,'agc_trig_delay', 511);
    else
        wl_interfaceCmd(nodes,'RF_ALL','rx_gain_mode','manual');
        user.RxGainRF = 1; %Rx RF Gain in [1:3]
        user.RxGainBB = 15; %Rx Baseband Gain in [0:31]
        bs.RxGainRF = 1; %Rx RF Gain in [1:3]
        bs.RxGainBB = 6; %Rx Baseband Gain in [0:31]
        wl_interfaceCmd(nodes(2),'RF_ALL','rx_gains',bs.RxGainRF,bs.RxGainBB);
        wl_interfaceCmd(nodes(3),'RF_ALL','rx_gains',user.RxGainRF,user.RxGainBB);

    end

    bs.txRadios = {[RFA,RFB,RFC,RFD], ...
                   [RFA,RFB]};

    bs.rxRadios = {[], ...
                   [RFC, RFD]};

    user.rxRadios = {[RFA]};

else
    bs = commNode([0 0]);
    user = commNode([0]);
    experiment.eth_trig = 0;
    sampFreq = 40e6;
    Ts = 1/sampFreq;
    txLength = 32768;

end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Signal processing to generate transmit signal
% Here, we can send any signal we want out of each of the 8 transmit 
% antennas. For visualization, we'll send "pink" noise of 1MHz out of 
% each, but centered at different parts of the 40MHz band.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% First generate the preamble for AGC. The preamble corresponds to the
% short symbols from the 802.11a PHY standard
shortSymbol_freq = [0 0 0 0 0 0 0 0 1+i 0 0 0 -1+i 0 0 0 -1-i 0 0 0 1-i 0 0 0 -1-i 0 0 0 1-i 0 0 0 0 0 0 0 1-i 0 0 0 -1-i 0 0 0 1-i 0 0 0 -1-i 0 0 0 -1+i 0 0 0 1+i 0 0 0 0 0 0 0].';
shortSymbol_freq = [zeros(32,1);shortSymbol_freq;zeros(32,1)];
shortSymbol_time = ifft(fftshift(shortSymbol_freq));
shortSymbol_time = (shortSymbol_time(1:32).')./max(abs(shortSymbol_time));
shortsyms_rep = repmat(shortSymbol_time,1,SHORT_SYMS_REPETITIONS);

preamble_single = shortsyms_rep;
preamble_single = preamble_single(:);

shifts = floor(linspace(0,31,numTxAntennas));
for k = 1:numTxAntennas
   %Shift preamble for each antenna so we don't have accidental beamforming
   preamble(:,k) = circshift(preamble_single,shifts(k));
end


% Second, generate the training frame
[pilot, trainSignal, pilotStartIndices] =  generateTrainSequence( ...
    numTxAntennas, pilotLength, pilotToneFrequency, pilotAmplitude,  guardIntervalLength, Ts);

% Second, generate the training frame
[pilot, trainSignal_single, pilotStartIndex_single] =  generateTrainSequence( ...
    1, pilotLength, pilotToneFrequency, pilotAmplitude,  guardIntervalLength, Ts);


% Correct for added preabmle and tx/rx delay
txPilotStartIndices = pilotStartIndices + TXRX_DELAY + length(preamble);

txPilotStartIndex_single = pilotStartIndex_single + TXRX_DELAY + length(preamble);

trainFrame = [preamble; trainSignal];

maxPayloadLength = txLength - length(preamble_single) - length(trainSignal_single);

% Now generate a payload
payloadLength = min(maxPayloadLength, PAYLOAD_LENGTH);

% create time index for the payload
t = [0:Ts:((payloadLength-1))*Ts].'; 

%5 MHz sinusoid as our "payload" for RFA
payload = payloadAmplitude*exp(t*j*2*pi*payloadToneFreq); 



preamble_end_rssi = floor((length(preamble) + TXRX_DELAY)/4);

preamble_rssi_measurement_window =  NUM_PREAMBLE_SAMPLES_LNA_SETTLE:preamble_end_rssi;


for i = 1:numPkts

    if experiment.USE_WARPLAB_TXRX == false
        experiment.generateChannelMatrices()
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Phase 1: Zero-forcing transmission
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Transmit and receive training signal using WARPLab
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    bs.set('txFrame', trainFrame);

    experiment.txrx_6x2x1(bs, user);

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Estimate channels from the received piolts
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    H_est_selfInt = estimateChannelMat(...
        numTxAntennas, numRxAntennas, bs.rx_IQ, txPilotStartIndices, pilot);

    H_est_user = estimateChannelMat(...
        numTxAntennas, numUsers, user.rx_IQ, txPilotStartIndices, pilot);

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Visualize received pilots
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    plot_IQ(bs.rx_IQ, bs.rx_power_dBm, numRxAntennas, 'BS Rx Pilots')
    plot_IQ(user.rx_IQ, user.rx_power_dBm, numUsers, 'User Rx Pilots')

    ZF.bs.uncodedpower = ...
        pow2db(mean(db2pow(bs.rx_power_dBm(preamble_rssi_measurement_window,:))));

    ZF.user.uncodedpower = ...
        pow2db(mean(db2pow(user.rx_power_dBm(preamble_rssi_measurement_window,:))));

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Zero-forcing a full data packet
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    % null combining
    selfIntNullspace = null(H_est_selfInt);


    if isempty(selfIntNullspace)
        ZF.precoder = ones(numTxAntennas,1)./sqrt(numTxAntennas);
        warning('Cannot zero force')
    else
        ZF.precoder = selfIntNullspace(:,1);
    end

    precoderPower = pow2db(sum(sum(abs(ZF.precoder).^2)));


    if abs(precoderPower - 0) > 1e-6 
        error('Zero-forcing precoder does not have unity power')
    end

    dataFrame = [preamble_single; trainSignal_single; payload];

    ZF.precodedDataFrame = (ZF.precoder * dataFrame .' ) .';

    bs.set('txFrame', ZF.precodedDataFrame);

    experiment.txrx_6x2x1(bs, user);
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Visualize received data frames
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    plot_IQ(bs.rx_IQ, bs.rx_power_dBm, numRxAntennas, 'BS Rx Data: zero-forcing')
    plot_IQ(user.rx_IQ, user.rx_power_dBm, numUsers, 'User Rx Data: zero-forcing')

    ZF.bs.precodedpower = ...
        pow2db(mean(db2pow(bs.rx_power_dBm(preamble_rssi_measurement_window,:))));

    ZF.user.precodedpower = ...
        pow2db(mean(db2pow(user.rx_power_dBm(preamble_rssi_measurement_window,:))));

    ZF.bs.beamGain = ZF.bs.precodedpower - ZF.bs.uncodedpower;
    ZF.user.beamGain = ZF.user.precodedpower - ZF.user.uncodedpower;
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Phase 2: Matched filter transmission
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Transmit and receive training signal using WARPLab
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    bs.set('txFrame', trainFrame);

    experiment.txrx_6x2x1(bs, user);

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Estimate channels from the received piolts
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    H_est_selfInt = estimateChannelMat(...
        numTxAntennas, numRxAntennas, bs.rx_IQ, txPilotStartIndices, pilot);

    H_est_user = estimateChannelMat(...
        numTxAntennas, numUsers, user.rx_IQ, txPilotStartIndices, pilot);

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Visualize received pilots
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    plot_IQ(bs.rx_IQ, bs.rx_power_dBm, numRxAntennas, 'BS Rx Pilots')
    plot_IQ(user.rx_IQ, user.rx_power_dBm, numUsers, 'User Rx Pilots')

    MF.bs.uncodedpower = ...
        pow2db(mean(db2pow(bs.rx_power_dBm(preamble_rssi_measurement_window,:))));

    MF.user.uncodedpower = ...
        pow2db(mean(db2pow(user.rx_power_dBm(preamble_rssi_measurement_window,:))));

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Matched filter transmission of full data packet to user
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    MF.precoder = ctranspose(H_est_user) ./sqrt(sum(sum(abs(H_est_user).^2)));


    precoderPower = pow2db(sum(sum(abs(MF.precoder).^2)));


    if abs(precoderPower - 0) > 1e-6 
        error('Zero-forcing precoder does not have unity power')
    end
  
    MF.precodedDataFrame = (MF.precoder * dataFrame .' ) .';

    bs.set('txFrame', MF.precodedDataFrame);

    experiment.txrx_6x2x1(bs, user);
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Visualize received data frames
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    plot_IQ(bs.rx_IQ, bs.rx_power_dBm, numRxAntennas, 'BS Rx Data: mathched filter')
    plot_IQ(user.rx_IQ, user.rx_power_dBm, numUsers, 'User Rx Data: mathched filter')
    
    MF.bs.precodedpower = ...
        pow2db(mean(db2pow(bs.rx_power_dBm(preamble_rssi_measurement_window,:))));

    MF.user.precodedpower = ...
        pow2db(mean(db2pow(user.rx_power_dBm(preamble_rssi_measurement_window,:))));

    MF.bs.beamGain = MF.bs.precodedpower - MF.bs.uncodedpower;
    MF.user.beamGain = MF.user.precodedpower - MF.user.uncodedpower;


    drawnow

    if (~RUN_CONTINOUSLY)
       break 
    end

end



