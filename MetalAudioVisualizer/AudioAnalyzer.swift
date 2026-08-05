import AVFoundation
import Accelerate
import SwiftUI
import Combine
import AVFoundation

class AudioAnalyzer: ObservableObject {
    
    let engine = AVAudioEngine()
    var vocalsPlayer = AVAudioPlayerNode()
    var bassPlayer = AVAudioPlayerNode()
    var drumsPlayer = AVAudioPlayerNode()
    var otherPlayer = AVAudioPlayerNode()
    
    @Published var vocalsLevel: Float = Constants.defaultAudioLevel
    @Published var bassLevel: Float = Constants.defaultAudioLevel
    @Published var drumsLevel: Float = Constants.defaultAudioLevel
    @Published var otherLevel: Float = Constants.defaultAudioLevel
    
    func start(vocals: String, bass: String, drums: String, other: String, ext: String) {
        guard
            let vocalsURL = Bundle.main.url(forResource: vocals, withExtension: ext),
            let bassURL = Bundle.main.url(forResource: bass, withExtension: ext),
            let drumsURL = Bundle.main.url(forResource: drums, withExtension: ext),
            let otherURL = Bundle.main.url(forResource: other, withExtension: ext),
            let vocalsFile = try? AVAudioFile(forReading: vocalsURL),
            let bassFile = try? AVAudioFile(forReading: bassURL),
            let drumsFile = try? AVAudioFile(forReading: drumsURL),
            let otherFile = try? AVAudioFile(forReading: otherURL)
        else {
            print("One or more files not found")
            return
        }
        
        setupPlayer(vocalsPlayer, format: vocalsFile.processingFormat, gain: Constants.vocalGain) { [weak self] level in
            self?.vocalsLevel = level
        }
        setupPlayer(bassPlayer, format: bassFile.processingFormat, gain: Constants.bassGain) { [weak self] level in
            self?.bassLevel = level
        }
        setupPlayer(drumsPlayer, format: drumsFile.processingFormat, gain: Constants.drumsGain) { [weak self] level in
            self?.drumsLevel = level
        }
        setupPlayer(otherPlayer, format: otherFile.processingFormat, gain: Constants.otherInstrumentsGain) { [weak self] level in
            self?.otherLevel = level
        } 
        
        try? engine.start()
        
        // Schedule all files
        vocalsPlayer.scheduleFile(vocalsFile, at: nil)
        bassPlayer.scheduleFile(bassFile, at: nil)
        drumsPlayer.scheduleFile(drumsFile, at: nil)
        otherPlayer.scheduleFile(otherFile, at: nil)
        
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + Constants.startTimeDelay)
        vocalsPlayer.play(at: startTime)
        bassPlayer.play(at: startTime)
        drumsPlayer.play(at: startTime)
        otherPlayer.play(at: startTime)
    }
    
    private func setupPlayer(_ player: AVAudioPlayerNode, format: AVAudioFormat, gain: Float, tapHandler: @escaping (Float) -> Void) {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        
        player.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            guard let data = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += data[i] * data[i]
            }
            let rms = sqrt(sum / Float(frameLength))
            let level = min(rms * 3.0 * gain, 1.0) // gain
            DispatchQueue.main.async {
                tapHandler(level)
            }
        }
    }
}
