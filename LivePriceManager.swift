import Foundation
import Combine

final class LivePriceManager {
    static let shared = LivePriceManager()

    // Map from ticker symbol to CoinGecko ID
    var geckoIDMap: [String: String] = [
        "btc": "bitcoin", "eth": "ethereum", "bnb": "binancecoin",
        "usdt": "tether",
        "busd": "binance-usd", "usdc": "usd-coin", "sol": "solana",
        "ada": "cardano", "xrp": "ripple", "doge": "dogecoin",
        "dot": "polkadot", "avax": "avalanche-2", "matic": "matic-network",
        "link": "chainlink", "xlm": "stellar", "bch": "bitcoin-cash",
        "trx": "tron", "uni": "uniswap", "etc": "ethereum-classic",
        "wbtc": "wrapped-bitcoin", "steth": "staked-ether",
        "wsteth": "wrapped-steth", "sui": "sui", "hype": "hyperliquid",
        "leo": "leo-token", "fil": "filecoin",
        "hbar": "hedera",
        "shib": "shiba-inu",
        "rlc": "iexec-rlc"
    ]

    private var pollingIDs: [String] = []

    // Timer for polling
    private var timerCancellable: AnyCancellable?

    // Subject to broadcast price dictionaries
    private let priceSubject = PassthroughSubject<[String: Double], Never>()
    var pricePublisher: AnyPublisher<[String: Double], Never> {
        priceSubject.eraseToAnyPublisher()
    }

    /// Alias for the internal pricePublisher so subscribers can use `.publisher`
    var publisher: AnyPublisher<[String: Double], Never> {
        pricePublisher
    }

    // Start polling CoinGecko for simple price updates
    func startPolling(ids: [String], interval: TimeInterval = 5) {
        stopPolling()
        self.pollingIDs = ids
        fetchPrices()
        timerCancellable = Timer
            .publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchPrices()
            }
    }

    // Stop the polling timer
    func stopPolling() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    /// Start a live feed for a single symbol using polling
    func connect(symbol: String, interval: TimeInterval = 5) {
        // Normalize symbol by removing USDT suffix if present
        let lower = symbol.lowercased()
        let clean = lower.hasSuffix("usdt") ? String(lower.dropLast(4)) : lower
        // Map to CoinGecko ID and begin polling
        let id = geckoIDMap[clean] ?? clean
        startPolling(ids: [id], interval: interval)
    }

    /// Stop the live feed
    func disconnect() {
        stopPolling()
    }

    // Fetch current prices for stored pollingIDs and send through the subject
    private func fetchPrices() {
        print("LivePriceManager: fetchPrices called for symbols: \(pollingIDs)")
        let idList = pollingIDs
            .map { symbol in
                let lower = symbol.lowercased()
                let clean = lower.hasSuffix("usdt") ? String(lower.dropLast(4)) : lower
                return geckoIDMap[clean] ?? clean
            }
            .joined(separator: ",")
        guard !idList.isEmpty else {
            print("LivePriceManager: idList is empty, aborting fetchPrices")
            return
        }
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price")
        components?.queryItems = [
            URLQueryItem(name: "ids", value: idList),
            URLQueryItem(name: "vs_currencies", value: "usd")
        ]
        guard let url = components?.url else {
            print("LivePriceManager: invalid URL components \(String(describing: components))")
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let dict = try? JSONDecoder().decode([String: [String: Double]].self, from: data)
            else { return }

            print("LivePriceManager: fetched raw dict: \(dict)")

            // Extract USD prices and broadcast
            let result = dict.compactMapValues { $0["usd"] }
            DispatchQueue.main.async {
                print("LivePriceManager: sending result to subject: \(result)")
                self.priceSubject.send(result)
            }
        }.resume()
    }
}
