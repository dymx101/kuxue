//
//  KXVoiceHUD.m
//  KuXue
//
//  Created by Yang Yi Feng on 11/23/13.
//  Copyright (c) 2013 kuxue.me. All rights reserved.
//

#import "KXVoiceHUD.h"

@implementation KXVoiceHUD

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
    if (self) {
        self.contentMode = UIViewContentModeRedraw;
		self.opaque = NO;
		self.backgroundColor = [UIColor clearColor];
		self.alpha = 0.0f;
        
        hudRect = CGRectMake(self.center.x - (HUD_SIZE / 2), self.center.y - (HUD_SIZE / 2), HUD_SIZE, HUD_SIZE);
        int x = (frame.size.width - HUD_SIZE) / 2;
        btnCancel = [[UIButton alloc] initWithFrame:CGRectMake(x, hudRect.origin.y + HUD_SIZE - CANCEL_BUTTON_HEIGHT, HUD_SIZE, CANCEL_BUTTON_HEIGHT)];
        [btnCancel setTitle:@"Cancel" forState:UIControlStateNormal];
        [btnCancel addTarget:self action:@selector(cancelled:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btnCancel];
        
        imgMicrophone = [UIImage imageNamed:@"VoiceHUD"];
        
        // Fill empty sound meters.
        for(int i = 0; i < SOUND_METER_COUNT; i++) {
            soundMeters[i] = 0;
        }
    }
    
    return self;
}

- (id)initWithParentView:(UIView *)view {
    return [self initWithFrame:view.bounds];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [self commitRecording];
}

- (void)startForFilePath:(NSString *)filePath {
    recordTime = 0;
    
    self.alpha = 1.0f;
    [self setNeedsDisplay];
    
	AVAudioSession *audioSession = [AVAudioSession sharedInstance];
	NSError *err = nil;
	[audioSession setCategory :AVAudioSessionCategoryPlayAndRecord error:&err];
	if(err){
        NSLog(@"audioSession: %@ %d %@", [err domain], [err code], [[err userInfo] description]);
        return;
	}
	[audioSession setActive:YES error:&err];
	err = nil;
	if(err){
        NSLog(@"audioSession: %@ %d %@", [err domain], [err code], [[err userInfo] description]);
        return;
	}
	
	recordSetting = [[NSMutableDictionary alloc] init];
	
	// Sets voice quality.
	[recordSetting setValue :[NSNumber numberWithInt:kAudioFormatAppleIMA4] forKey:AVFormatIDKey];
	[recordSetting setValue:[NSNumber numberWithFloat:16000.0] forKey:AVSampleRateKey];
	[recordSetting setValue:[NSNumber numberWithInt: 1] forKey:AVNumberOfChannelsKey];
    
	// Should activate these settings if using kAudioFormatLinearPCM format.
	// [recordSetting setValue :[NSNumber numberWithInt:16] forKey:AVLinearPCMBitDepthKey];
	// [recordSetting setValue :[NSNumber numberWithBool:NO] forKey:AVLinearPCMIsBigEndianKey];
	// [recordSetting setValue :[NSNumber numberWithBool:NO] forKey:AVLinearPCMIsFloatKey];
    
    NSLog(@"Recording at: %@", filePath);
	recorderFilePath = filePath;
    
	NSURL *url = [NSURL fileURLWithPath:recorderFilePath];
    
	err = nil;
	
	NSData *audioData = [NSData dataWithContentsOfFile:[url path] options: 0 error:&err];
	if(audioData)
	{
		NSFileManager *fm = [NSFileManager defaultManager];
		[fm removeItemAtPath:[url path] error:&err];
	}
	
	err = nil;
	recorder = [[ AVAudioRecorder alloc] initWithURL:url settings:recordSetting error:&err];
	if(!recorder){
        NSLog(@"recorder: %@ %d %@", [err domain], [err code], [[err userInfo] description]);
        UIAlertView *alert =
        [[UIAlertView alloc] initWithTitle: @"Warning" message: [err localizedDescription] delegate: nil cancelButtonTitle:@"Ok" otherButtonTitles:nil];
        [alert show];
        return;
	}
	
	[recorder setDelegate:self];
	[recorder prepareToRecord];
	recorder.meteringEnabled = YES;
	
	BOOL audioHWAvailable = audioSession.inputAvailable;
	if (! audioHWAvailable) {
        UIAlertView *cantRecordAlert =
        [[UIAlertView alloc] initWithTitle: @"Warning" message: @"Audio input hardware not available" delegate: nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [cantRecordAlert show];
        return;
	}
	
	[recorder recordForDuration:(NSTimeInterval) 120];
	
	timer = [NSTimer scheduledTimerWithTimeInterval:WAVE_UPDATE_FREQUENCY target:self selector:@selector(updateMeters) userInfo:nil repeats:YES];
}

- (void)updateMeters {
    [recorder updateMeters];
    
    NSLog(@"meter:%5f", [recorder averagePowerForChannel:0]);
    if (([recorder averagePowerForChannel:0] < -60.0) && (recordTime > 3.0)) {
        [self commitRecording];
        return;
    }
    
    recordTime += WAVE_UPDATE_FREQUENCY;
    [self addSoundMeterItem:[recorder averagePowerForChannel:0]];
    
}

- (void)cancelRecording {
    if ([self.delegate respondsToSelector:@selector(voiceRecordCancelledByUser:)]) {
        [self.delegate voiceRecordCancelledByUser:self];
    }
    
    [recorder stop];
}

- (void)commitRecording {
    [recorder stop];
    [timer invalidate];
    
    if ([self.delegate respondsToSelector:@selector(KXVoiceHUD:voiceRecorded:length:)]) {
        [self.delegate KXVoiceHUD:self voiceRecorded:recorderFilePath length:recordTime];
    }
    
    self.alpha = 0.0;
    [self setNeedsDisplay];
}

- (void)cancelled:(id)sender {
    self.alpha = 0.0;
    [self setNeedsDisplay];
    
    [timer invalidate];
    [self cancelRecording];
}

- (void)setCancelButtonTitle:(NSString *)title {
    btnCancel.titleLabel.text = title;
}

#pragma mark - Sound meter operations

- (void)shiftSoundMeterLeft {
    for(int i=0; i<SOUND_METER_COUNT - 1; i++) {
        soundMeters[i] = soundMeters[i+1];
    }
}

- (void)addSoundMeterItem:(int)lastValue {
    [self shiftSoundMeterLeft];
    [self shiftSoundMeterLeft];
    soundMeters[SOUND_METER_COUNT - 1] = lastValue;
    soundMeters[SOUND_METER_COUNT - 2] = lastValue;
    
    [self setNeedsDisplay];
}

#pragma mark - Drawing operations

- (void)drawRect:(CGRect)rect {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    UIColor *strokeColor = [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:1.0];
    UIColor *fillColor = [UIColor colorWithRed:0.5827 green:0.5827 blue:0.5827 alpha:1.0];
    UIColor *gradientColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.8];
    UIColor *color = [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:1.0];
    
    NSArray *gradientColors = [NSArray arrayWithObjects: (id)fillColor.CGColor, (id)gradientColor.CGColor, nil];
    CGFloat gradientLocations[] = {0, 1};
    CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, (__bridge CFArrayRef)gradientColors, gradientLocations);
    
    UIBezierPath *border = [UIBezierPath bezierPathWithRoundedRect:hudRect cornerRadius:10.0];
    CGContextSaveGState(context);
    [border addClip];
    CGContextDrawRadialGradient(context, gradient,
                                CGPointMake(hudRect.origin.x + HUD_SIZE / 2, 120), 10,
                                CGPointMake(hudRect.origin.x + HUD_SIZE / 2, 195), 215,
                                kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    
    CGContextRestoreGState(context);
    [strokeColor setStroke];
    border.lineWidth = 1.0;
    [border stroke];
    
    // Draw the sound meter wave.
    [[UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.4] set];
    
    CGContextSetLineWidth(context, 3.0);
    CGContextSetLineJoin(context, kCGLineJoinRound);
    
    int baseLine = 250;
    int multiplier = 1;
    int maxLengthOfWave = 50;
    int maxValueOfMeter = 70;
    for(CGFloat x = SOUND_METER_COUNT - 1; x >= 0; x--)
    {
        multiplier = ((int)x % 2) == 0 ? 1 : -1;
        
        CGFloat y = baseLine + ((maxValueOfMeter * (maxLengthOfWave - abs(soundMeters[(int)x]))) / maxLengthOfWave) * multiplier;
        
        if(x == SOUND_METER_COUNT - 1) {
            CGContextMoveToPoint(context, x * (HUD_SIZE / SOUND_METER_COUNT) + hudRect.origin.x + 10, y);
            CGContextAddLineToPoint(context, x * (HUD_SIZE / SOUND_METER_COUNT) + hudRect.origin.x + 7, y);
        }
        else {
            CGContextAddLineToPoint(context, x * (HUD_SIZE / SOUND_METER_COUNT) + hudRect.origin.x + 10, y);
            CGContextAddLineToPoint(context, x * (HUD_SIZE / SOUND_METER_COUNT) + hudRect.origin.x + 7, y);
        }
    }
    
    CGContextStrokePath(context);
    
    // Draw a title.
    [color setFill];
    
    NSMutableParagraphStyle *textStyle = [[NSMutableParagraphStyle defaultParagraphStyle] mutableCopy];
    [textStyle setLineBreakMode:NSLineBreakByWordWrapping];
    [textStyle setAlignment:NSTextAlignmentCenter];
    UIFont *textFont = [UIFont systemFontOfSize:24];
    UIColor *textColor = [UIColor whiteColor];
    NSDictionary *attributes = @{NSFontAttributeName:textFont, NSForegroundColorAttributeName:textColor, NSParagraphStyleAttributeName:textStyle};
    [self.title drawInRect:CGRectInset(hudRect, 0, 25) withAttributes:attributes];
    
    [imgMicrophone drawAtPoint:CGPointMake(hudRect.origin.x + hudRect.size.width/2 - imgMicrophone.size.width / 2, hudRect.origin.y + hudRect.size.height / 2 - imgMicrophone.size.height / 2)];
    
    [[UIColor colorWithWhite:0.8 alpha:1.0] setFill];
    UIBezierPath *line = [UIBezierPath bezierPath];
    [line moveToPoint:CGPointMake(hudRect.origin.x, hudRect.origin.y + HUD_SIZE - CANCEL_BUTTON_HEIGHT)];
    [line addLineToPoint:CGPointMake(hudRect.origin.x + HUD_SIZE, hudRect.origin.y + HUD_SIZE - CANCEL_BUTTON_HEIGHT)];
    [line setLineWidth:3.0];
    [line stroke];
}

- (void)playRecording:(NSURL *)url {
    [self cancelRecording];
    
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
    
    NSError *error;
    self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
    [self.player prepareToPlay];
    [self.player play];
}

@end
