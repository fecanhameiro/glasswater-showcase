//
//  SoundService.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 08/03/26.
//

import AVFoundation

enum DuckSound: String, CaseIterable {
    case splash = "duck_waterfowl_landing"
    case quack = "duck_quack"
    case quackSingle1 = "duck_quack_single_1"
    case quackSingle2 = "duck_quack_single_2"
    case flapping = "duck_flapping_wings"
}

protocol SoundServicing: Sendable {
    func play(_ sound: DuckSound)
    func playRandomQuackSingle()
}

@MainActor
final class SoundService: SoundServicing {
    private var players: [DuckSound: AVAudioPlayer] = [:]
    private var isConfigured = false

    init() {
        // Pre-load audio players in background to avoid first-play freeze
        let vols = Self.volumes
        Task.detached(priority: .utility) {
            var loaded: [DuckSound: AVAudioPlayer] = [:]
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
            #endif
            for sound in DuckSound.allCases {
                guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "mp3"),
                      let player = try? AVAudioPlayer(contentsOf: url) else { continue }
                player.volume = vols[sound] ?? 0.35
                player.prepareToPlay()
                loaded[sound] = player
            }
            await MainActor.run { [loaded] in
                guard !self.isConfigured else { return }
                self.players = loaded
                self.isConfigured = true
            }
        }
    }

    private static let volumes: [DuckSound: Float] = [
        .splash: 0.25,
        .quack: 0.25,
        .quackSingle1: 0.30,
        .quackSingle2: 0.30,
        .flapping: 0.60
    ]

    func play(_ sound: DuckSound) {
        if !isConfigured {
            configurePlayers()
        }
        guard let player = players[sound] else { return }
        player.currentTime = 0
        player.play()
    }

    func playRandomQuackSingle() {
        play(Bool.random() ? .quackSingle1 : .quackSingle2)
    }

    private func configurePlayers() {
        isConfigured = true
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        #endif
        for sound in DuckSound.allCases {
            guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "mp3"),
                  let player = try? AVAudioPlayer(contentsOf: url) else {
                AppLog.error("SoundService: missing audio asset '\(sound.rawValue).mp3'", category: .userAction)
                continue
            }
            player.volume = Self.volumes[sound] ?? 0.35
            player.prepareToPlay()
            players[sound] = player
        }
    }
}

final class PreviewSoundService: SoundServicing {
    nonisolated deinit {} // Workaround for Swift bug #87316
    func play(_ sound: DuckSound) {}
    func playRandomQuackSingle() {}
}
