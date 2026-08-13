
%PTB Setup
Screen('Preference', 'SkipSyncTests', 0); %Setting to skip synching test, 0-to enable, 1-to skip
Screen('Preference', 'VisualDebugLevel', 0); 
KbName('UnifyKeyNames');
PsychDefaultSetup(2);

% Setup experimental screen
data = struct('SubjectNum',{},'blockNum',{},'frameRate',{},'TimeStamp',{},'onTarget',{},'Txi',{},'Tyi',{},'Tzi',{});

%Random Motion Path for Target
rmp1 = readtable('rmp_1.csv');
rmp2 = readtable('rmp_2.csv');
rmp3 = readtable('rmp_3.csv');
rmp4 = readtable('rmp_4.csv');
rmp5 = readtable('rmp_5.csv');
rmp6 = readtable('rmp_6.csv');
rmp7 = readtable('rmp_7.csv');
rmp8 = readtable('rmp_8.csv');
rmp9 = readtable('rmp_9.csv');
rmp10 = readtable('rmp_10.csv');

[xTarget,yTarget] = randomMotion(rmp1);

% data(1).SubjectNum = input("Subject #: ");
% data(1).blockNum = input("Block #: ");
% data(1).frameRate = input("Frame Rate: ");
screenID = max(Screen('Screens')); %Retrieve screen ID of the secondary display.
[win, rect] = PsychImaging('OpenWindow', screenID, [0 0 0]);% Opens default PTB window on desired display with a black background
Screen('BlendFunction', win, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);%Anti-aliasing and transparency
ifi = Screen('GetFlipInterval', win); %Inter Frame Interval. Measures exact duration of a single frame on monitor in seconds. 
[widthMM, heightMM] = Screen('DisplaySize', screenID);

[targetImg,~,targetAlpha] = imread('food_0001_sphere_300.png');
if ~isempty(targetAlpha)
    targetImg(:,:,4) = targetAlpha;
end
targetTexture = Screen('MakeTexture', win, targetImg);
[imgHeight,imgWidth,~] = size(targetImg);
imgAspect = imgWidth/imgHeight;
destRect = [100 100 500 500]; % [x1 y1 x2 y2]

%Start Screen 
startText = ['Welcome to the Tracking Task \n\n' ...
    'Move the mouse to control the cross-hair\n'...
    'Track the dot and attempt to keep it in the white rectangular borders of the crosshair \n\n' ...
    'Press Space to begin']; %Instructional text
Screen('TextSize',win,40);
Screen('TextFont',win,'Arial');
DrawFormattedText(win,startText,'center','center',[0,1,0]); %Draws text on screen in green
Screen('Flip',win);

%Wait for space-bar press to start program
KbReleaseWait;
while true
    [keyIsDown,~,keyCode] = KbCheck;
    if keyIsDown && keyCode(KbName('SPACE'))
        break
    end
end
KbReleaseWait;


%---------------Experimental Section----------------------------- 


[xCenter, yCenter] = RectCenter(rect); %define the center coordinates of the screen based on screen dimensions
%Hide the cursor and set the control to the center of the screen
HideCursor;
SetMouse(xCenter, yCenter, win);
Screen('Flip', win);

%Frame Rate Properties
frameRate = 100;
frameDuration = 1/frameRate;

%Camera Properties
cameraX = 0; 
cameraY = 0;
sensitivity = 30;

%Target Properties
targetX = xCenter;      % starting X position
targetY = yCenter;      % starting Y position
targetSize = 20;
targetColor = [255 0 0];
% motion parameters
speed = 200;                     % pixels per frame 
direction = rand * 2*pi;       % random initial direction
changeProb = 1;             % probability per frame to change direction

% Background Dots Properties
b_dotSize = 5;
b_dotColor = [0,1,0];
numBgDots = 10000;          
% Global Boundaries
worldMin = -20000; 
worldMax =  20000;
bgDotsX = worldMin + (worldMax - worldMin) * rand(numBgDots, 1);
bgDotsY = worldMin + (worldMax - worldMin) * rand(numBgDots, 1);
bgDotsZ = worldMin + (worldMax - worldMin) * rand(numBgDots, 1);


%background dot density calculation
mmPerPixel = mean([widthMM/rect(3), heightMM/rect(4)]); 
mmPerPixelSq = mmPerPixel^2; %area of one pixel

worldArea = (worldMax - worldMin)^2;          % total world area (px^2, world units)
screenAreaPx = rect(3) * rect(4);             % screen area in pixels^2
screenAreaMM2 = screenAreaPx * mmPerPixelSq;  % screen area in mm^2

expectedVisibleDots = numBgDots * (screenAreaPx / worldArea);
dotDensity_mm2 = expectedVisibleDots / screenAreaMM2;

% Cross-hair Properties
crsHr_width = 300;
crsHr_height = 100;
crsHr_color = [255,255,255];
crsHr_thickness = 4;


%Depth Properties
cameraZ = 0;
depthStep = 5;
targetZ = 500;
refDistance = 800;
targetBaseSize = targetSize;
minTargetSize = 4;
maxTargetSize = 150;
vbl = Screen('Flip', win);

%Frame Skipping Variables
lastMotionTime = vbl; %Time stamp of last frame flip
screenFlips = zeros(20,1); %Array of last 20 flip timestamps
avgFPS_20 = 0; %avg from screenFlips
framesPerUpdate = max(1,round((frameDuration)/ifi)); %number of frames per flip
frameCounter = 0;
motionCounter = 1;

joy = vrjoystick(1);   % 1 = first joystick detected


%MAIN LOOP
while true

    %Display Expected frame rate 
    expectedFrameRate = sprintf('Expected Frame Rate = %d FPS \n',frameRate);
    Screen('TextSize',win,20);
    Screen('TextFont',win,'Arial');
    DrawFormattedText(win,expectedFrameRate,rect(3)-700,30,[255,255,255]);

    %Display Actual Frame Rate
    RealFPS = sprintf('Real Frame Rate = %.2f FPS \n',avgFPS_20);
    Screen('TextSize',win,20);
    Screen('TextFont',win,'Arial');
    DrawFormattedText(win,RealFPS,rect(3)-300,30,[255,255,255]);

    %Continously check for 'esc' press to exit program
    [keyIsDown, ~, keyCode] = KbCheck;
    if keyIsDown && keyCode(KbName('ESCAPE'))
        break;
    end

    %Display events on screen only at the set frame rate
    frameCounter = frameCounter + 1; %Increment frame counter per screen flip
    if frameCounter >= framesPerUpdate
        frameCounter = 0; %reset counter
        motionCounter = motionCounter + framesPerUpdate;
        motionCounter = min(motionCounter, length(xTarget));

        % Read all axes and buttons
        [axes, buttons, pov] = read(joy);

        % Typical Warthog mapping:
        jx = axes(1);   % X axis (left/right)
        jy = axes(2);   % Y axis (forward/back)

        % Deadzone
        deadzone = 0.03;
        if abs(jx) < deadzone, jx = 0; end
        if abs(jy) < deadzone, jy = 0; end

        % Apply movement
        cameraX = cameraX + jx * sensitivity;
        cameraY = cameraY + jy * sensitivity;


        % % Read mouse controller movement
        % [mx, my] = GetMouse(win);
        % dx = mx - xCenter;
        % dy = my - yCenter;
        % % Re-center mouse
        % SetMouse(xCenter, yCenter, win);
        %
        % % Move camera with the mouse
        % cameraX = cameraX + dx * sensitivity;
        % cameraY = cameraY + dy * sensitivity;

        [~,~,keyCode] = KbCheck;
        if keyCode(KbName('upArrow'))
            cameraZ = cameraZ + depthStep;
        elseif keyCode(KbName('downArrow'))
            cameraZ = cameraZ - depthStep;
        end

        distance = targetZ - cameraZ;
        distance = max(distance,1);
        apparentSize = targetBaseSize * (refDistance/distance);
        apparentSize = min(max(apparentSize, minTargetSize), maxTargetSize);

        %Convert background dots to screen coordinates
        relX = bgDotsX - cameraX;
        relY = bgDotsY - cameraY;
        relZ = bgDotsZ - cameraZ;
        relZ = max(relZ,1);

        scale = refDistance ./ relZ;

        screen_b_DotsX = xCenter + relX .* scale;
        screen_b_DotsY = yCenter + relY .* scale;

        dotSizes = b_dotSize .* scale;
        dotSizes = max(dotSizes, 1);          % prevent too-small dots
        dotSizes = min(dotSizes, 150);        % optional: prevent giant dots


        %Only draw background dots that are on-screen to optimize
        %performance
        onScreen = screen_b_DotsX > 0 & screen_b_DotsX < rect(3) & screen_b_DotsY > 0 & screen_b_DotsY < rect(4); %background dots must stay within the x and y boundaries of the screen
        visibleDots = [screen_b_DotsX(onScreen)'; screen_b_DotsY(onScreen)'];
        visibleSizes = dotSizes(onScreen);

        %Draw target
        dtMotion = framesPerUpdate*ifi; %delta motion described by time in seconds for the number of frames drawn
        % [targetX,targetY,speed,direction,changeProb] = randomMotion(targetX,targetY,speed,direction,changeProb,dtMotion); %Produce random motion for position of the target
        %Convert target coordinates to screen coordinates
        % screen_targetX = targetX - cameraX;
        % screen_targetY = targetY - cameraY;
        screen_targetX = xTarget(motionCounter) - cameraX;
        screen_targetY = yTarget(motionCounter) - cameraY;

        destWidth = apparentSize * 2;
        destHeight = destWidth/imgAspect;
        destRect = CenterRectOnPointd([0 0 destWidth destHeight], screen_targetX, screen_targetY);



        instant_fps = 1/(vbl - lastMotionTime);% Calculate instantaneous frames per second
        screenFlips(end+1) = instant_fps; %Append to overall screen flip list
        %Once screenFlips reaches 20, calculate the mean and reset
        if numel(screenFlips) >= 20
            avgFPS_20 = mean(screenFlips);
            screenFlips = [];
        end
        lastMotionTime = vbl;
        % data.TimeStamp(end+1) = vbl;

    end
  
    Screen('DrawDots', win, visibleDots, visibleSizes, b_dotColor, [], 2); % Draw background dots

  
    Screen('DrawTexture', win, targetTexture, [], destRect);
    % Screen('DrawDots', win, [screen_targetX; screen_targetY], apparentSize, targetColor, [], 2); %Draw target

    %Draw crosshair
    DrawCrossHair(crsHr_height,crsHr_height,crsHr_color, crsHr_thickness,xCenter,yCenter,win);

    % data.Txi(end+1) = screen_targetX;
    % data.Tyi(end+1) = screen_targetY;
    % data.Tzi = 0;
    % data.onTarget(end+1) = checkTarget(screen_targetX,screen_targetY,xCenter,yCenter,crsHr_height,crsHr_height);


    vbl = Screen('Flip', win);

end

Screen('Close', targetTexture);

sca;

function DrawCrossHair(width, height, color, thickness, xCenter, yCenter, win)
    halfW = width/2;
    halfH = height/2;

    % How far the corner brackets extend along each edge (tune this ratio)
    bracketLenX = halfW * 0.6;
    bracketLenY = halfH * 0.6;

    % How far the crosshair lines extend beyond the square
    lineExtentX = halfW * 1.4;
    lineExtentY = halfH * 1.4;

    % --- Full horizontal line (passes through, extends past square) ---
    Screen('DrawLine', win, color, ...
        xCenter - lineExtentX, yCenter, ...
        xCenter + lineExtentX, yCenter, thickness);

    % --- Full vertical line (passes through, extends past square) ---
    Screen('DrawLine', win, color, ...
        xCenter, yCenter - lineExtentY, ...
        xCenter, yCenter + lineExtentY, thickness);

    % --- Top-left bracket ---
    Screen('DrawLine', win, color, xCenter - halfW, yCenter - halfH, xCenter - halfW + bracketLenX, yCenter - halfH, thickness); % top edge
    Screen('DrawLine', win, color, xCenter - halfW, yCenter - halfH, xCenter - halfW, yCenter - halfH + bracketLenY, thickness); % left edge

    % --- Top-right bracket ---
    Screen('DrawLine', win, color, xCenter + halfW, yCenter - halfH, xCenter + halfW - bracketLenX, yCenter - halfH, thickness);
    Screen('DrawLine', win, color, xCenter + halfW, yCenter - halfH, xCenter + halfW, yCenter - halfH + bracketLenY, thickness);

    % --- Bottom-left bracket ---
    Screen('DrawLine', win, color, xCenter - halfW, yCenter + halfH, xCenter - halfW + bracketLenX, yCenter + halfH, thickness);
    Screen('DrawLine', win, color, xCenter - halfW, yCenter + halfH, xCenter - halfW, yCenter + halfH - bracketLenY, thickness);

    % --- Bottom-right bracket ---
    Screen('DrawLine', win, color, xCenter + halfW, yCenter + halfH, xCenter + halfW - bracketLenX, yCenter + halfH, thickness);
    Screen('DrawLine', win, color, xCenter + halfW, yCenter + halfH, xCenter + halfW, yCenter + halfH - bracketLenY, thickness);
end
% function [newX,newY,speed,direction,changeProb] = randomMotion(x,y,speed,direction,changeProb,dt)
%     if rand < (changeProb *dt *60)
%         direction = direction + randn * 0.5;   % small random turn
%     end
% 
%     %Velocity
%     vx = speed * cos(direction);
%     vy = speed * sin(direction);
% 
%     %Update position
%     newX = x + (vx*dt);
%     newY = y + (vy*dt);
% 
% end

function [x,y] = randomMotion(motionFile)
    x = motionFile.X*1000;
    y = motionFile.Y*1000;
end

function isOnTarget = checkTarget(targetX,targetY,xCenter,yCenter,crsHairHeight,crsHairWidth)
    withinX = targetX < xCenter + crsHairWidth/2 && targetX > xCenter - crsHairWidth/2;
    withinY = targetY < yCenter + crsHairHeight/2 && targetY > yCenter - crsHairHeight/2;
    if withinX && withinY
        isOnTarget = true;
    else
        isOnTarget = false;
    end
end




