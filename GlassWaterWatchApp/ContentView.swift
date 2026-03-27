//
//  ContentView.swift
//  GlassWaterWatch Watch App
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel: WatchHomeViewModel

    init(connectivityService: (any WatchConnectivityServicing)? = nil) {
        _viewModel = State(initialValue: WatchHomeViewModel(connectivityService: connectivityService))
    }

    var body: some View {
        TabView {
            WatchHomeView(viewModel: viewModel)
            WatchHistoryView(viewModel: viewModel)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
    }
}

#Preview {
    ContentView()
}
