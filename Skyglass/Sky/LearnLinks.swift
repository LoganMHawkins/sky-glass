import Foundation

/// Quick-reference reading for each object: encyclopedia entries, NASA pages and live trackers.
struct LearnLink: Identifiable {
    let title: String
    let source: String
    let symbol: String
    let url: URL
    var id: String { url.absoluteString }
}

enum LearnLinks {
    static func wikipedia(_ article: String, title: String = "Wikipedia") -> LearnLink? {
        let slug = article.replacingOccurrences(of: " ", with: "_")
        guard let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/wiki/\(encoded)") else { return nil }
        return LearnLink(title: title, source: "en.wikipedia.org", symbol: "book.closed", url: url)
    }

    private static func link(_ title: String, _ source: String, _ symbol: String, _ url: String) -> LearnLink? {
        URL(string: url).map { LearnLink(title: title, source: source, symbol: symbol, url: $0) }
    }

    // MARK: Stars

    private static let greek: [Character: String] = [
        "α": "Alpha", "β": "Beta", "γ": "Gamma", "δ": "Delta", "ε": "Epsilon", "ζ": "Zeta", "η": "Eta", "θ": "Theta",
        "ι": "Iota", "κ": "Kappa", "λ": "Lambda", "μ": "Mu", "ξ": "Xi", "π": "Pi", "σ": "Sigma", "τ": "Tau", "υ": "Upsilon", "φ": "Phi",
    ]
    private static let superscripts: [Character: String] = ["¹": "1", "²": "2"]
    private static let genitive: [String: String] = [
        "And": "Andromedae", "Aql": "Aquilae", "Ari": "Arietis", "Aur": "Aurigae", "Boo": "Boötis", "Car": "Carinae", "Cas": "Cassiopeiae",
        "Cen": "Centauri", "Cep": "Cephei", "Cet": "Ceti", "CMa": "Canis Majoris", "CMi": "Canis Minoris", "CrB": "Coronae Borealis",
        "Cru": "Crucis", "Crv": "Corvi", "Cyg": "Cygni", "Dra": "Draconis", "Eri": "Eridani", "Gem": "Geminorum", "Gru": "Gruis",
        "Hya": "Hydrae", "Leo": "Leonis", "Lib": "Librae", "Lyr": "Lyrae", "Oph": "Ophiuchi", "Ori": "Orionis", "Pav": "Pavonis",
        "Peg": "Pegasi", "Per": "Persei", "Phe": "Phoenicis", "PsA": "Piscis Austrini", "Pup": "Puppis", "Sco": "Scorpii",
        "Ser": "Serpentis", "Sgr": "Sagittarii", "Tau": "Tauri", "TrA": "Trianguli Australis", "UMa": "Ursae Majoris",
        "UMi": "Ursae Minoris", "Vel": "Velorum", "Vir": "Virginis",
    ]

    /// "γ² Sgr" → "Gamma2 Sagittarii". Wikipedia redirects these to the star's article, which avoids
    /// ambiguous proper names like Gienah or Castor.
    static func bayerArticle(_ bayer: String) -> String? {
        let parts = bayer.split(separator: " ")
        guard parts.count == 2, let first = parts[0].first, let letter = greek[first],
              let con = genitive[String(parts[1])] else { return nil }
        let index = parts[0].dropFirst().compactMap { superscripts[$0] }.joined()
        return "\(letter)\(index) \(con)"
    }

    static func forStar(_ s: Star) -> [LearnLink] {
        [wikipedia(bayerArticle(s.bayer) ?? s.name, title: "\(s.name) on Wikipedia"),
         wikipedia("\(s.constellation) (constellation)", title: "The constellation \(s.constellation)"),
         wikipedia("Stellar classification", title: "What “\(s.spectral)” means")].compactMap { $0 }
    }

    // MARK: Solar System

    static func forBody(_ body: Body) -> [LearnLink] {
        let article = body == .mercury ? "Mercury (planet)" : body.name
        var links: [LearnLink?] = [
            link("\(body.name) at NASA Science", "science.nasa.gov", "globe.americas", "https://science.nasa.gov/\(body.rawValue)/"),
            wikipedia(article, title: "\(body.name) on Wikipedia"),
        ]
        switch body {
        case .sun:
            links.append(link("Today's Sun from SDO", "sdo.gsfc.nasa.gov", "sun.max", "https://sdo.gsfc.nasa.gov/data/"))
            links.append(link("Space weather now", "swpc.noaa.gov", "bolt.horizontal", "https://www.swpc.noaa.gov/"))
        case .moon:
            links.append(link("Moon phase calendar", "timeanddate.com", "moonphase.waxing.gibbous", "https://www.timeanddate.com/moon/phases/"))
            links.append(wikipedia("Lunar mare", title: "The Moon's dark seas"))
        case .saturn:
            links.append(wikipedia("Rings of Saturn", title: "Saturn's rings"))
        case .jupiter:
            links.append(wikipedia("Great Red Spot", title: "The Great Red Spot"))
        default:
            break
        }
        return links.compactMap { $0 }
    }

    // MARK: Deep sky

    private static let deepSkyArticles: [String: String] = [
        "M13": "Messier 13", "M22": "Messier 22", "Mel 25": "Hyades (star cluster)", "Sgr A*": "Sagittarius A*",
        "NGC 104": "47 Tucanae", "NGC 869": "Double Cluster",
    ]

    static func forDeepSky(_ d: DeepSkyObject) -> [LearnLink] {
        var links: [LearnLink?] = [wikipedia(deepSkyArticles[d.catalog] ?? d.name, title: "\(d.name) on Wikipedia")]
        if d.catalog.hasPrefix("M"), let n = Int(d.catalog.dropFirst()) {
            links.append(link("Hubble's view of \(d.catalog)", "science.nasa.gov", "camera.aperture",
                              "https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-messier-catalog/messier-\(n)/"))
        }
        if d.catalog == "Sgr A*" {
            links.append(link("The first image of Sgr A*", "eventhorizontelescope.org", "circle.dotted", "https://eventhorizontelescope.org/"))
        }
        return links.compactMap { $0 }
    }

    // MARK: Satellites

    static func forSatellite(_ sat: Satellite, design: SatDesign) -> [LearnLink] {
        var links: [LearnLink?] = []
        switch sat.norad {
        case 25544:
            links += [link("Space Station at NASA", "nasa.gov", "person.2", "https://www.nasa.gov/international-space-station/"),
                      link("Spot the Station alerts", "spotthestation.nasa.gov", "bell", "https://spotthestation.nasa.gov/")]
        case 48274:
            links.append(wikipedia("Tiangong space station", title: "Tiangong on Wikipedia"))
        case 20580:
            links += [link("Hubble at NASA", "science.nasa.gov", "camera.aperture", "https://science.nasa.gov/mission/hubble/"),
                      wikipedia("Hubble Space Telescope", title: "Hubble on Wikipedia")]
        default:
            if design.isStarlink {
                links += [link("Starlink", "starlink.com", "wifi", "https://www.starlink.com/"),
                          wikipedia("Starlink", title: "Starlink on Wikipedia")]
            }
        }
        links += [link("Live tracking map", "n2yo.com", "map", "https://www.n2yo.com/satellite/?s=\(sat.norad)"),
                  link("Passes & orbit details", "heavens-above.com", "list.bullet.rectangle", "https://www.heavens-above.com/SatInfo.aspx?satid=\(sat.norad)"),
                  link("Catalogue record", "celestrak.org", "number", "https://celestrak.org/satcat/table-satcat.php?CATNR=\(sat.norad)")]
        return links.compactMap { $0 }
    }
}

extension SkyModel {
    func learnLinks(for id: String) -> [LearnLink] {
        if let s = StarCatalog.byID[id] { return LearnLinks.forStar(s) }
        if let d = DeepSkyCatalog.byID[id] { return LearnLinks.forDeepSky(d) }
        if id.hasPrefix("body:"), let b = Body(rawValue: String(id.dropFirst(5))) { return LearnLinks.forBody(b) }
        if let sat = satellites.byID[id] { return LearnLinks.forSatellite(sat, design: sat.design) }
        return []
    }
}
