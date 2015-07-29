//
//  ViewController.m
//  NKCamera
//
//  Created by nanoka____ on 2015/07/28.
//  Copyright (c) 2015年 nanoka____. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>
@end

//フォーカスと露出 https://icons8.com/web-app/7025/inactive-state
//カメラ向き変更 https://icons8.com/web-app/2210/switch-camera
//フラッシュ https://icons8.com/web-app/6704/lightning-bolt
//撮影ボタン https://icons8.com/web-app/2874/integrated-webcam-filled

typedef enum {
    TapedViewTypeFocus,
    TapedViewTypeExposure,
    TapedViewTypeNone
} TapedViewType;

/*========================================================
 ; ViewController
 ========================================================*/
@implementation ViewController {
    AVCaptureDeviceInput *videoInput;
    AVCaptureVideoDataOutput *videoDataOutput;
    AVCaptureSession *session;
    UIImageView *previewImageView;
    BOOL CAMERA_FRONT;
    
    UINavigationBar *oNavigationBar;
    UIToolbar *oToolbar;
    
    TapedViewType viewType;
    UIImageView *focusView;
    UIImageView *exposureView;
    
    BOOL adjustingExposure;
    
    UIImageView *takePhotoOverlay;
    
    UIButton *flashButton;
    dispatch_queue_t flashQueue;
    BOOL FLASH_MODE;
}

/*--------------------------------------------------------
 ; dealloc : 解放
 ;      in :
 ;     out :
 --------------------------------------------------------*/
-(void)dealloc {
    videoInput = nil;
    videoDataOutput = nil;
    session = nil;
    previewImageView = nil;
    
    oNavigationBar = nil;
    oToolbar = nil;
    
    focusView = nil;
    exposureView = nil;
    
    flashButton = nil;
    takePhotoOverlay = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] removeObserver:self
                                                                       forKeyPath:@"adjustingExposure"];
}

/*--------------------------------------------------------
 ; viewDidLoad : 初回Viewが読み込まれた時
 ;          in :
 ;         out :
 --------------------------------------------------------*/
-(void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.view.backgroundColor = [UIColor whiteColor];
    viewType = TapedViewTypeNone;
    //queue
    flashQueue = dispatch_queue_create("com.coma-tech.takingPhotoQueue", DISPATCH_QUEUE_SERIAL);
    
    //露出のプロパティを監視する
    [[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] addObserver:self
                                                                    forKeyPath:@"adjustingExposure"
                                                                       options:NSKeyValueObservingOptionNew
                                                                       context:nil];
    
    //マルチタスクから復帰したときに呼ばれる
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationBecomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    //マルチタスクから復帰したときに呼ばれる
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationResignActive)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    //フラッシュ変更ボタン
    flashButton = [UIButton buttonWithType:UIButtonTypeCustom];
    flashButton.frame = CGRectMake(0, 0, 44, 44);
    [flashButton setImage:[UIImage imageNamed:@"flash"] forState:UIControlStateNormal];
    [flashButton addTarget:self action:@selector(changeFlashMode:) forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *changeFlashButton = [[UIBarButtonItem alloc] initWithCustomView:flashButton];
    
    //カメラ向き変更ボタン
    UIBarButtonItem *changeCameraButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"change_camera"]
                                                                           style:UIBarButtonItemStylePlain
                                                                          target:self
                                                                          action:@selector(changeCamera:)];
    
    //ナビゲーションバー
    oNavigationBar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 44+20)];
    [self.view addSubview:oNavigationBar];
    UINavigationItem *naviItem = [[UINavigationItem alloc] initWithTitle:@"NKCamera"];
    naviItem.leftBarButtonItems = @[changeFlashButton];
    naviItem.rightBarButtonItems = @[changeCameraButton];
    [oNavigationBar setItems:@[naviItem]];
    
    //スペース
    UIBarButtonItem *spacer = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    
    //撮影ボタン
    UIBarButtonItem *takePhotoButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"shutter"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(takePhoto:)];
    
    //ツールバーを生成
    oToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, self.view.frame.size.height-44, self.view.bounds.size.width, 44)];
    oToolbar.items = @[spacer,takePhotoButton,spacer];
    [self.view addSubview:oToolbar];
    
    //プレビュー用のビューを生成
    previewImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0,
                                                                     oNavigationBar.frame.origin.y+oNavigationBar.frame.size.height,
                                                                     self.view.bounds.size.width,
                                                                     self.view.bounds.size.height - oToolbar.frame.size.height - (oNavigationBar.frame.origin.y+oNavigationBar.frame.size.height))];
    [self.view addSubview:previewImageView];
    
    //フォーカスビュー
    focusView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
    focusView.userInteractionEnabled = YES;
    focusView.center = previewImageView.center;
    focusView.image = [UIImage imageNamed:@"focus_circle"];
    [self.view addSubview:focusView];
    
    //露出
    exposureView = [[UIImageView alloc] initWithFrame:focusView.frame];
    exposureView.userInteractionEnabled = YES;
    exposureView.image = [UIImage imageNamed:@"exposure_circle"];
    [self.view addSubview:exposureView];
    
    //撮影時の黒いオーバーレイ
    takePhotoOverlay = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width/2, self.view.frame.size.height/2)];
    takePhotoOverlay.center = self.view.center;
    takePhotoOverlay.layer.borderWidth = 1.0;
    takePhotoOverlay.layer.borderColor = [UIColor whiteColor].CGColor;
    takePhotoOverlay.backgroundColor = [UIColor clearColor];
    takePhotoOverlay.contentMode = UIViewContentModeScaleAspectFit;
    takePhotoOverlay.alpha = 0.0;
    [self.view addSubview:takePhotoOverlay];
    
    //撮影開始
    [self setupAVCapture];
}

/*--------------------------------------------------------
 ; changeFlashMode : フラッシュのモードを変更する
 ;              in : (id)sender
 ;             out :
 --------------------------------------------------------*/
-(void)changeFlashMode:(id)sender {
    FLASH_MODE = !FLASH_MODE;
    if(FLASH_MODE){
        [flashButton setImage:[UIImage imageNamed:@"flash_on"] forState:UIControlStateNormal];
    }else{
        [flashButton setImage:[UIImage imageNamed:@"flash"] forState:UIControlStateNormal];
    }
}

/*--------------------------------------------------------
 ; changeCamera : カメラ向き変更ボタン
 ;           in : (id)sender
 ;          out :
 --------------------------------------------------------*/
-(void)changeCamera:(id)sender {
    //今と反対の向きを判定
    CAMERA_FRONT = !CAMERA_FRONT;
    AVCaptureDevicePosition position = AVCaptureDevicePositionBack;
    if(CAMERA_FRONT){
        position = AVCaptureDevicePositionFront;
    }
    //セッションからvideoInputの取り消し
    [session removeInput:videoInput];
    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *captureDevice = nil;
    for (AVCaptureDevice *device in videoDevices){
        if(device.position == position){
            captureDevice = device;
            if(CAMERA_FRONT){
                //フロントカメラになった
                if(FLASH_MODE){
                    //フラッシュをOFFにする
                    [self changeFlashMode:nil];
                }
                flashButton.enabled = NO;
            }else{
                flashButton.enabled = YES;
            }
            break;
        }
    }

    //  couldn't find one on the front, so just get the default video device.
    if(!captureDevice) {
        captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    videoInput = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice
                                                       error:nil];
    if(videoInput) {
        [session addInput:videoInput];
    }
}

/*--------------------------------------------------------
 ; takePhoto : 撮影ボタン
 ;        in : (id)sender
 ;       out :
 --------------------------------------------------------*/
-(void)takePhoto:(id)sender {
//シャッター音(必要な場合コメント外してください)
//    AudioServicesPlaySystemSound(1108);
    
    if(FLASH_MODE && !CAMERA_FRONT){
        dispatch_sync(flashQueue, ^{
            AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
            if ([camera hasTorch] && [camera hasFlash]){
                NSError *error = nil;
                if([camera lockForConfiguration:&error]) {
                    [camera setTorchMode:AVCaptureTorchModeOn];
                    [camera unlockForConfiguration];
                }
            }
            sleep(1);
        });
    }
    
    // アルバムに画像を保存
    SEL selector = @selector(onCompleteCapture:didFinishSavingWithError:contextInfo:);
    UIImageWriteToSavedPhotosAlbum(previewImageView.image, self, selector, nil);
}

/*--------------------------------------------------------
 ; onCompleteCapture : 画像保存完了時
 ;                in : (UIImage *)screenImage
 ;                   : (NSError *)error
 ;                   : (void *)contextInfo
 ;               out :
 --------------------------------------------------------*/
-(void)onCompleteCapture:(UIImage *)screenImage didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    if(!error && screenImage){
        //保存成功
        //フラッシュ消灯
        if(FLASH_MODE && !CAMERA_FRONT){
            dispatch_sync(flashQueue, ^{
                Class captureDeviceClass = NSClassFromString(@"AVCaptureDevice");
                if(captureDeviceClass != nil){
                    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
                    if([device hasTorch] && [device hasFlash]){
                        NSError *error = nil;
                        if([device lockForConfiguration:&error]) {
                            [device setTorchMode:AVCaptureTorchModeOff];
                            [device setFlashMode:AVCaptureFlashModeOff];
                            [device unlockForConfiguration];
                        }
                    }
                }
            });
        }
        
        //保存画像オーバーレイ
        takePhotoOverlay.image = screenImage;
        [UIView animateWithDuration:0.3
                         animations:^{
                             takePhotoOverlay.alpha = 1.0;
                         }
                         completion:^(BOOL finished){
                             dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                 // 処理内容
                                 [UIView animateWithDuration:0.3
                                                  animations:^{
                                                      takePhotoOverlay.alpha = 0.0;
                                                  }
                                                  completion:^(BOOL finished){
                                                      takePhotoOverlay.image = nil;
                                                  }
                                  ];
                             });
                         }
         ];
    }
}

/*--------------------------------------------------------
 ; setupAVCapture : カメラキャプチャーの設定
 ;             in :
 ;            out :
 --------------------------------------------------------*/
-(void)setupAVCapture {
    NSError *error = nil;
    
    //入力と出力からキャプチャーセッションを作成
    session = [[AVCaptureSession alloc] init];
    
    //画像のサイズ
    session.sessionPreset = AVCaptureSessionPresetHigh;
    
    //カメラからの入力を作成
    AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    //カメラからの入力を作成し、セッションに追加
    videoInput = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
    [session addInput:videoInput];
    
    //画像への出力を作成し、セッションに追加
    videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [session addOutput:videoDataOutput];
    
    //ビデオ出力のキャプチャの画像情報のキューを設定
    dispatch_queue_t queue = dispatch_queue_create("myQueue", NULL);
    [videoDataOutput setAlwaysDiscardsLateVideoFrames:TRUE];
    [videoDataOutput setSampleBufferDelegate:self queue:queue];
    
    //ビデオへの出力の画像は、BGRAで出力
    videoDataOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInt:kCVPixelFormatType_32BGRA]};
    
    //1秒あたり15回画像をキャプチャ
    if([camera lockForConfiguration:&error]){
        camera.activeVideoMinFrameDuration = CMTimeMake(1, 15);
        [camera unlockForConfiguration];
    }
}

/*--------------------------------------------------------
 ; imageFromSampleBuffer : SampleBufferを画像に変換する
 ;                    in : (CMSampleBufferRef)sampleBuffer
 ;                   out : (UIImage *)image
 --------------------------------------------------------*/
-(UIImage *)imageFromSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    // ピクセルバッファのベースアドレスをロックする
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    // Get information of the image
    uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
    
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    // RGBの色空間
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef newContext = CGBitmapContextCreate(baseAddress,
                                                    width,
                                                    height,
                                                    8,
                                                    bytesPerRow,
                                                    colorSpace,
                                                    kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    
    CGImageRef cgImage = CGBitmapContextCreateImage(newContext);
    
    CGContextRelease(newContext);
    CGColorSpaceRelease(colorSpace);
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    
    UIImage *image = [UIImage imageWithCGImage:cgImage scale:1.0 orientation:UIImageOrientationRight];
    
    CGImageRelease(cgImage);
    
    return image;
}

/*========================================================
 ; AVCaptureVideoDataOutputSampleBufferDelegate
 ========================================================*/
/*--------------------------------------------------------
 ; didOutputSampleBuffer : 新しいキャプチャの情報が追加された時
 ;                    in : (AVCaptureOutput *)captureOutput
 ;                       : (CMSampleBufferRef)sampleBuffer
 ;                       : (AVCaptureConnection *)connection
 ;                   out :
 --------------------------------------------------------*/
-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    // キャプチャしたフレームからCGImageを作成
    UIImage *image = [self imageFromSampleBuffer:sampleBuffer];
    
    // 画像を画面に表示
    dispatch_async(dispatch_get_main_queue(), ^{
        previewImageView.image = image;
    });
}

/*========================================================
 ; UIResponder
 ========================================================*/
/*--------------------------------------------------------
 ; touchesBegan : Viewが触られた時
 ;           in : (NSSet *)touches
 ;              : (UIEvent *)event
 ;          out :
 --------------------------------------------------------*/
-(void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    //触られたViewを判定する
    UITouch *touch = [touches anyObject];
    if(touch.view == focusView){
        viewType = TapedViewTypeFocus;
    }else if(touch.view == exposureView){
        viewType = TapedViewTypeExposure;
    }else{
        viewType = TapedViewTypeNone;
    }
}

/*--------------------------------------------------------
 ; touchesMoved : Viewが触られている時
 ;           in : (NSSet *)touches
 ;              : (UIEvent *)event
 ;          out :
 --------------------------------------------------------*/
-(void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if(viewType != TapedViewTypeNone){
        UITouch *touch = [touches anyObject];
        CGPoint location = [touch locationInView:self.view];
        if(location.x > focusView.frame.size.width/2 &&
           location.x < self.view.frame.size.width-focusView.frame.size.width/2 &&
           location.y > focusView.frame.size.height/2+oNavigationBar.frame.origin.y+oNavigationBar.frame.size.height &&
           location.y < self.view.frame.size.height-oToolbar.frame.size.height-focusView.frame.size.height/2){
            //フォーカスか露出をカメラ映像内で移動させる
            if(viewType == TapedViewTypeFocus){
                focusView.center = location;
            }else if(viewType == TapedViewTypeExposure){
                exposureView.center = location;
            }
        }
    }
}

/*--------------------------------------------------------
 ; touchesCancelled : Viewを触るのをキャンセルされた
 ;               in : (NSSet *)touches
 ;                  : (UIEvent *)event
 ;              out :
 --------------------------------------------------------*/
-(void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    if(viewType != TapedViewTypeNone){
        //フォーカスか露出の調整中にキャンセルされた時、正常終了のメソッドも呼ぶ
        [self touchesEnded:touches withEvent:event];
    }
}

/*--------------------------------------------------------
 ; touchesEnded : Viewを触り終わった時
 ;           in : (NSSet *)touches
 ;              : (UIEvent *)event
 ;          out :
 --------------------------------------------------------*/
-(void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if(viewType != TapedViewTypeNone){
        //対象座標を作成
        UITouch *touch = [touches anyObject];
        CGPoint location = [touch locationInView:self.view];
        CGSize viewSize = self.view.bounds.size;
        CGPoint pointOfInterest = CGPointMake(location.y / viewSize.height,
                                              1.0 - location.x / viewSize.width);
        if(viewType == TapedViewTypeFocus){
            //フォーカスを合わせる
            AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
            NSError *error = nil;
            if ([camera isFocusPointOfInterestSupported] && [camera isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
                if ([camera lockForConfiguration:&error]) {
                    camera.focusPointOfInterest = pointOfInterest;
                    camera.focusMode = AVCaptureFocusModeAutoFocus;
                    [camera unlockForConfiguration];
                }
            }
        }else if(viewType == TapedViewTypeExposure){
            //露出を合わせる
            AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
            NSError *error = nil;
            if ([camera isExposurePointOfInterestSupported] && [camera isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]){
                adjustingExposure = YES;
                if ([camera lockForConfiguration:&error]) {
                    camera.exposurePointOfInterest = pointOfInterest;
                    camera.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
                    [camera unlockForConfiguration];
                }
            }
        }
        viewType = TapedViewTypeNone;
    }
}

/*========================================================
 ; UIApplication
 ========================================================*/
/*--------------------------------------------------------
 ; applicationBecomeActive : アプリがフォアグラウンドで有効な状態になった時
 ;                      in :
 ;                     out :
 --------------------------------------------------------*/
-(void)applicationBecomeActive {
    //カメラの起動
    if(session){
        [session startRunning];
    }
}

/*--------------------------------------------------------
 ; applicationResignActive : アプリがバックグラウンドで無効な状態になった時
 ;                      in :
 ;                     out :
 --------------------------------------------------------*/
-(void)applicationResignActive {
    //カメラの停止
    if(session){
        [session stopRunning];
    }
}

/*========================================================
 ; NSObject(NSKeyValueObserving)
 ========================================================*/
/*--------------------------------------------------------
 ; observeValueForKeyPath : 露出のプロパティが変更された時
 ;                     in : (NSString *)keyPath
 ;                        : (id)object
 ;                        : (NSDictionary *)change
 ;                        : (void *)context
 ;                    out :
 --------------------------------------------------------*/
-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    //露出が決定していない時は処理を返す
    if (!adjustingExposure) {
        return;
    }
    
    //露出が決定した
    if ([keyPath isEqual:@"adjustingExposure"]) {
        if ([[change objectForKey:NSKeyValueChangeNewKey] boolValue] == NO) {
            //露出を固定する
            adjustingExposure = NO;
            AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
            NSError *error = nil;
            if ([camera lockForConfiguration:&error]) {
                [camera setExposureMode:AVCaptureExposureModeLocked];
                [camera unlockForConfiguration];
            }
        }
    }
}

@end
