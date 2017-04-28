//
//  ImageExtractor.swift
//  pixelsynth
//
//  Created by Malte Bünz on 28.04.17.
//  Copyright © 2017 Malte Bünz. All rights reserved.
//

import UIKit
import AVFoundation

//protocol FrameExtractorDelegate: class {
//    func captured(image: UIImage)
//}

class FrameExtractor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    private let position = AVCaptureDevicePosition.back
    private let quality = AVCaptureSessionPresetHigh
    
    private var permissionGranted = false
    public let captureSession = AVCaptureSession()
    private let context = CIContext()
    
    // Queues
    private let sessionQueue = DispatchQueue(label: Queues.sessionQueue.rawValue)
    private let videoDataOutputQueue = DispatchQueue(label: Queues.videoDataQueue.rawValue,
                                                     qos: .userInitiated,
                                                     attributes: [],
                                                     autoreleaseFrequency: .workItem)
    private var isSessionRunning = false
    
    // Delegates
    weak var delegate: FrameExtractorDelegate?
    
    // Observers
    var runtimeErrorHandlingObserver: AnyObject?
    
    // Falgs
    private var renderingEnabled = true    
    
    // MARK: Lifecycle
    override init() {
        super.init()
        checkPermission()
        sessionQueue.async { [unowned self] in
            self.configureSession()
            self.captureSession.startRunning()
        }
    }
    
    // MARK: AVSession configuration
    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo) {
        case .authorized:
            permissionGranted = true
        case .notDetermined:
            requestPermission()
        default:
            permissionGranted = false
        }
    }
    
    private func requestPermission() {
        sessionQueue.suspend()
        AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo) { [unowned self] granted in
            self.permissionGranted = granted
            self.sessionQueue.resume()
        }
    }
    
    /***/
    func didEnterBackground(notification: NSNotification) {
        // Free up resources
        videoDataOutputQueue.async { [unowned self] in
            self.renderingEnabled = false
        }
    }
    
    /***/
    func willEnterForground(notification: NSNotification) {
        videoDataOutputQueue.async { [unowned self] in
            self.renderingEnabled = true
        }
    }
    
    private func configureSession() {
        guard permissionGranted else { return }
        captureSession.sessionPreset = quality
        guard let captureDevice = selectCaptureDevice() else { return }
        guard let captureDeviceInput = try? AVCaptureDeviceInput(device: captureDevice) else { return }
        guard captureSession.canAddInput(captureDeviceInput) else { return }
        captureSession.addInput(captureDeviceInput)
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample buffer"))
        guard captureSession.canAddOutput(videoOutput) else { return }
        captureSession.addOutput(videoOutput)
        guard let connection = videoOutput.connection(withMediaType: AVFoundation.AVMediaTypeVideo) else { return }
        guard connection.isVideoOrientationSupported else { return }
        guard connection.isVideoMirroringSupported else { return }
        connection.videoOrientation = .portrait
        connection.isVideoMirrored = position == .front
    }
    
    private func selectCaptureDevice() -> AVCaptureDevice? {
        let backCamera: AVCaptureDeviceType = .builtInWideAngleCamera
        let position: AVCaptureDevicePosition = .back
        return AVCaptureDeviceDiscoverySession(deviceTypes: [backCamera],
                                               mediaType: AVMediaTypeVideo,
                                               position: position).devices.first!
    }
    
    /**
     */
    func startCamera() {
        sessionQueue.async { [unowned self] in
            self.captureSession.startRunning()
        }
    }
    
    /**
     */
    func teardownCamera() {
        sessionQueue.async { [unowned self] in
            self.captureSession.stopRunning()
        }
    }
    
    
    // MARK: Sample buffer to UIImage conversion
    private func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        guard let uiImage = imageFromSampleBuffer(sampleBuffer: sampleBuffer) else { return }
        DispatchQueue.main.async { [unowned self] in
            self.delegate?.captured(image: uiImage)
        }
    }
}
