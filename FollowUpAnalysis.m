%% Tracking Task Follow-Up Analysis
clear;
clc;
 
%% Select data file
[file, path] = uigetfile({'*.csv;*.xlsx', 'Data files (*.csv, *.xlsx)'});
 
if isequal(file,0)
    error('No file selected.');
end
 
filename = fullfile(path,file);
data = readtable(filename);
 
%% Basic trial information
taskMode = string(data.taskMode(1));
 
%% ============================================================
% 1. EUCLIDEAN DISTANCE BETWEEN TARGET AND CURSOR
% =============================================================
 
switch taskMode
 
    case "Lateral"
 
        % Target - cursor error in X and Y
        errorX = data.Txi - data.Cxi;
        errorY = data.Tyi - data.Cyi;
 
        % Euclidean distance at each sample
        euclideanDistance = sqrt(errorX.^2 + errorY.^2);
 
        % Signals for lag analysis
        target1 = data.Txi;
        cursor1 = data.Cxi;
 
        target2 = data.Tyi;
        cursor2 = data.Cyi;
 
        axis1Name = "X";
        axis2Name = "Y";
 
 
    case "Depth"
 
        % X error
        errorX = data.Txi - data.Cxi;
 
        % Tzi includes the 500-unit baseline.
        % Remove it for tracking analysis.
        targetZ = data.Tzi - 500;
 
        % Z error
        errorZ = targetZ - data.Czi;
 
        % Euclidean distance in X/Z space
        euclideanDistance = sqrt(errorX.^2 + errorZ.^2);
 
        % Signals for lag analysis
        target1 = data.Txi;
        cursor1 = data.Cxi;
 
        target2 = targetZ;
        cursor2 = data.Czi;
 
        axis1Name = "X";
        axis2Name = "Z";
 
 
    otherwise
        error('Unknown task mode: %s', taskMode);
end
 
%% ============================================================
% 2. RMS TRACKING ERROR
% =============================================================
 
rmsTrackingError = sqrt(mean(euclideanDistance.^2,'omitnan'));
 
%% ============================================================
% 3. TIME ON TARGET
% =============================================================
 
% Use actual timestamps rather than assuming every frame lasted
% exactly 1 / nominal frame rate.
 
time = data.TimeStamp;
 
% Duration represented by each sample
dt = [diff(time); median(diff(time),'omitnan')];
 
% Total time on target in seconds
timeOnTarget_seconds = sum(dt(data.onTarget == 1),'omitnan');
 
% Total analysed duration
totalTime_seconds = sum(dt,'omitnan');
 
% Percentage of trial spent on target
percentOnTarget = 100 * timeOnTarget_seconds / totalTime_seconds;
 
%% ============================================================
% 4. CROSS-CORRELATION LAG
% =============================================================
 
% Remove any rows with invalid timestamps
validTime = isfinite(time);
 
time = time(validTime);
target1 = target1(validTime);
cursor1 = cursor1(validTime);
target2 = target2(validTime);
cursor2 = cursor2(validTime);
 
% Remove duplicate timestamps if any
[time,uniqueIdx] = unique(time,'stable');
 
target1 = target1(uniqueIdx);
cursor1 = cursor1(uniqueIdx);
target2 = target2(uniqueIdx);
cursor2 = cursor2(uniqueIdx);
 
% Estimate achieved sampling rate from timestamps
Fs = 1 / median(diff(time));
 
% Create evenly sampled time vector
timeUniform = (time(1):1/Fs:time(end))';
 
% Interpolate all trajectories onto the same time base
target1_uniform = interp1(time,target1,timeUniform,'linear');
cursor1_uniform = interp1(time,cursor1,timeUniform,'linear');
 
target2_uniform = interp1(time,target2,timeUniform,'linear');
cursor2_uniform = interp1(time,cursor2,timeUniform,'linear');
 
% Remove mean
target1_uniform = target1_uniform - mean(target1_uniform,'omitnan');
cursor1_uniform = cursor1_uniform - mean(cursor1_uniform,'omitnan');
 
target2_uniform = target2_uniform - mean(target2_uniform,'omitnan');
cursor2_uniform = cursor2_uniform - mean(cursor2_uniform,'omitnan');
 
% Maximum lag to examine
maxLagSeconds = 2;
maxLagSamples = round(maxLagSeconds * Fs);
 
%% Axis 1 cross-correlation
 
% Order is cursor, target
[r1,lags] = xcorr(cursor1_uniform, ...
                  target1_uniform, ...
                  maxLagSamples, ...
                  'coeff');
 
[peakCorrelation1,idx1] = max(r1);
 
lagSamples1 = lags(idx1);
lagSeconds1 = lagSamples1 / Fs;
 
%% Axis 2 cross-correlation
 
[r2,~] = xcorr(cursor2_uniform, ...
               target2_uniform, ...
               maxLagSamples, ...
               'coeff');
 
[peakCorrelation2,idx2] = max(r2);
 
lagSamples2 = lags(idx2);
lagSeconds2 = lagSamples2 / Fs;
 
%% Overall 2-D lag
 
% Average the normalized cross-correlations from both dimensions
meanCrossCorrelation = (r1 + r2) / 2;
 
[peakCorrelationOverall,idxOverall] = max(meanCrossCorrelation);
 
lagSamplesOverall = lags(idxOverall);
lagSecondsOverall = lagSamplesOverall / Fs;
 
%% ============================================================
% 5. DISPLAY RESULTS
% =============================================================
 
fprintf('\n----------------------------------------\n');
fprintf('TRACKING TASK RESULTS\n');
fprintf('----------------------------------------\n');
 
fprintf('Task mode: %s\n',taskMode);
fprintf('Estimated sampling rate: %.2f Hz\n',Fs);
 
fprintf('\nTRACKING ERROR\n');
fprintf('RMS Euclidean tracking error: %.3f\n', ...
    rmsTrackingError);
 
fprintf('\nTIME ON TARGET\n');
fprintf('Time on target: %.3f s\n', ...
    timeOnTarget_seconds);
 
fprintf('Percent on target: %.2f %%\n', ...
    percentOnTarget);
 
fprintf('\nLAG\n');
 
fprintf('%s-axis lag: %.4f s (peak r = %.3f)\n', ...
    axis1Name,lagSeconds1,peakCorrelation1);
 
fprintf('%s-axis lag: %.4f s (peak r = %.3f)\n', ...
    axis2Name,lagSeconds2,peakCorrelation2);
 
fprintf('Overall lag: %.4f s (peak r = %.3f)\n', ...
    lagSecondsOverall,peakCorrelationOverall);
 
fprintf('----------------------------------------\n');
 
%% ============================================================
% 6. SAVE TRIAL SUMMARY
% =============================================================
 
results = table( ...
    string(file), ...
    taskMode, ...
    Fs, ...
    rmsTrackingError, ...
    timeOnTarget_seconds, ...
    percentOnTarget, ...
    lagSeconds1, ...
    lagSeconds2, ...
    lagSecondsOverall, ...
    peakCorrelation1, ...
    peakCorrelation2, ...
    peakCorrelationOverall);
 
results.Properties.VariableNames = { ...
    'File', ...
    'TaskMode', ...
    'SamplingRate_Hz', ...
    'RMSTrackingError', ...
    'TimeOnTarget_s', ...
    'PercentOnTarget', ...
    ['Lag_' char(axis1Name) '_s'], ...
    ['Lag_' char(axis2Name) '_s'], ...
    'OverallLag_s', ...
    ['PeakCorrelation_' char(axis1Name)], ...
    ['PeakCorrelation_' char(axis2Name)], ...
    'PeakCorrelationOverall'};
 
summaryFile = fullfile(path, ...
    ['Summary_' erase(file,{'.csv','.xlsx'}) '.xlsx']);
 
writetable(results,summaryFile);
 
%% ============================================================
% 7. SAVE SAMPLE-BY-SAMPLE DISTANCE
% =============================================================
 
data.EuclideanDistance = euclideanDistance;
 
detailedFile = fullfile(path, ...
    ['Analyzed_' erase(file,{'.csv','.xlsx'}) '.xlsx']);
 
writetable(data,detailedFile);
has context menu

