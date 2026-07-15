import SwiftUI

// MARK: - Acknowledgements / Credits
// Required by the licenses of the bundled open-source work: Stockfish (GPLv3), the OFL fonts, and
// the Lichess piece art (each set carries its own author + license). Reachable from Settings.

struct AcknowledgementsView: View {
    var onClose: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL

    private struct Credit: Identifiable {
        let id = UUID()
        let name: String
        let author: String
        let license: String
        let url: String
    }

    // Lichess piece sets shipped in Resources/Pieces (folder id → author + license).
    private let pieces: [Credit] = [
        .init(name: "Cburnett",   author: "Colin M.L. Burnett",          license: "GPLv2+",       url: "https://github.com/lichess-org/lila/tree/master/public/piece/cburnett"),
        .init(name: "Merida",     author: "Armando Hernandez Marroquin", license: "GPLv2+",       url: "https://github.com/lichess-org/lila/tree/master/public/piece/merida"),
        .init(name: "Fantasy",    author: "Maurizio Monge",              license: "MIT",          url: "https://github.com/lichess-org/lila/tree/master/public/piece/fantasy"),
        .init(name: "Chessnut",   author: "Alexis Luengas",              license: "Apache-2.0",   url: "https://github.com/lichess-org/lila/tree/master/public/piece/chessnut"),
        .init(name: "Celtic",     author: "Maurizio Monge",              license: "MIT",          url: "https://github.com/lichess-org/lila/tree/master/public/piece/celtic"),
        .init(name: "Spatial",    author: "Maurizio Monge",              license: "MIT",          url: "https://github.com/lichess-org/lila/tree/master/public/piece/spatial"),
        .init(name: "Pirouetti",  author: "pirouetti",                   license: "AGPLv3+",      url: "https://github.com/lichess-org/lila/tree/master/public/piece/pirouetti"),
        .init(name: "Kiwen Suwi", author: "neverRare",                   license: "CC BY 4.0",    url: "https://github.com/lichess-org/lila/tree/master/public/piece/kiwen-suwi"),
        .init(name: "Totoy",      author: "Kosal Sen",                   license: "CC BY 4.0",    url: "https://github.com/lichess-org/lila/tree/master/public/piece/totoy"),
        .init(name: "Papercut",   author: "Nikolay Anzarov",             license: "CC BY 4.0",    url: "https://github.com/lichess-org/lila/tree/master/public/piece/papercut"),
        .init(name: "Letter",     author: "usolando",                    license: "AGPLv3+",      url: "https://github.com/lichess-org/lila/tree/master/public/piece/letter"),
        .init(name: "Shapes",     author: "flugsio",                     license: "CC BY-SA 4.0", url: "https://github.com/lichess-org/lila/tree/master/public/piece/shapes"),
        .init(name: "Pixel",      author: "therealqtpi",                 license: "AGPLv3+",      url: "https://github.com/lichess-org/lila/tree/master/public/piece/pixel"),
        .init(name: "RhosGFX",    author: "RhosGFX",                     license: "CC0 1.0",      url: "https://github.com/lichess-org/lila/tree/master/public/piece/rhosgfx"),
        .init(name: "MPChess",    author: "Maxime Chupin",               license: "GPLv3+",       url: "https://github.com/lichess-org/lila/tree/master/public/piece/mpchess"),
    ]

    // Additional free piece sets sourced outside Lichess (each with its own author + license).
    private let otherPieces: [Credit] = [
        .init(name: "Kaneo",          author: "Kadagaden",                 license: "CC BY 4.0",    url: "https://github.com/Kadagaden/chess-pieces"),
        .init(name: "Kaneo Midnight", author: "Kadagaden",                 license: "CC BY 4.0",    url: "https://github.com/Kadagaden/chess-pieces"),
        .init(name: "1 Kbyte Gambit", author: "Kadagaden",                 license: "CC BY 4.0",    url: "https://github.com/Kadagaden/chess-pieces"),
        .init(name: "Buch",           author: "Buch (Michele Bucelli)",    license: "CC BY 3.0",    url: "https://opengameart.org/content/chess-pieces-set"),
        .init(name: "OpenMoji",       author: "OpenMoji contributors",     license: "CC BY-SA 4.0", url: "https://openmoji.org"),
        .init(name: "Firi",           author: "James Faure",               license: "CC BY 4.0",    url: "https://github.com/jfaure/Firi-pieceset"),
    ]

    // CC BY-NC-SA piece sets from Lichess (lila). Legal to bundle only while Tabia is distributed FREE
    // of charge (no ads, in-app purchases, or paid tier). Converted PNGs inherit CC BY-NC-SA; credited here.
    private let ncPieces: [Credit] = [
        .init(name: "Maestro",   author: "sadsnake1",          license: "CC BY-NC-SA 4.0", url: "https://github.com/lichess-org/lila/tree/master/public/piece/maestro"),
        .init(name: "Staunty",   author: "sadsnake1",          license: "CC BY-NC-SA 4.0", url: "https://github.com/lichess-org/lila/tree/master/public/piece/staunty"),
        .init(name: "Caliente",  author: "avi",                license: "CC BY-NC-SA 4.0", url: "https://github.com/avi-0/caliente"),
        .init(name: "California", author: "Jerry S.",          license: "CC BY-NC-SA 4.0", url: "https://sites.google.com/view/jerrychess/home"),
        .init(name: "Cooke",     author: "fejfar",             license: "CC BY-NC-SA 4.0", url: "https://github.com/fejfar"),
        .init(name: "Gioco",     author: "sadsnake1",          license: "CC BY-NC-SA 4.0", url: "https://github.com/lichess-org/lila/tree/master/public/piece/gioco"),
        .init(name: "Horsey",    author: "cham, michael1241",  license: "CC BY-NC-SA 4.0", url: "https://github.com/lichess-org/lila/tree/master/public/piece/horsey"),
        .init(name: "Dubrovny",  author: "sadsnake1",          license: "CC BY-NC-SA 4.0", url: "https://github.com/lichess-org/lila/tree/master/public/piece/dubrovny"),
        .init(name: "Fresca",    author: "sadsnake1",          license: "CC BY-NC-SA 4.0", url: "https://github.com/lichess-org/lila/tree/master/public/piece/fresca"),
        .init(name: "Tatiana",   author: "sadsnake1",          license: "CC BY-NC-SA 4.0", url: "https://github.com/lichess-org/lila/tree/master/public/piece/tatiana"),
        .init(name: "Cardinal",  author: "sadsnake1",          license: "CC BY-NC-SA 4.0", url: "https://github.com/lichess-org/lila/tree/master/public/piece/cardinal"),
        .init(name: "IC Pieces", author: "sadsnake1",          license: "CC BY-NC-SA 4.0", url: "https://github.com/lichess-org/lila/tree/master/public/piece/icpieces"),
        .init(name: "Anarcandy", author: "caderek",            license: "CC BY-NC-SA 4.0", url: "https://github.com/caderek"),
        .init(name: "Monarchy",  author: "slither77",          license: "CC BY-NC-SA 4.0", url: "https://github.com/slither77"),
        .init(name: "Disguised", author: "danegraphics",       license: "CC BY-NC-SA 4.0", url: "https://github.com/lichess-org/lila/tree/master/public/piece/disguised"),
        .init(name: "xkcd",      author: "Randall Munroe",     license: "CC BY-NC-SA 2.5", url: "https://xkcd.com/license.html"),
    ]

    private let software: [Credit] = [
        .init(name: "Stockfish", author: "The Stockfish developers", license: "GPLv3", url: "https://stockfishchess.org"),
    ]

    private let fonts: [Credit] = [
        .init(name: "Newsreader",      author: "Production Type", license: "SIL Open Font License 1.1", url: "https://fonts.google.com/specimen/Newsreader"),
        .init(name: "Instrument Sans", author: "Rodrigo Fuenzalida & Jordan Egstad", license: "SIL Open Font License 1.1", url: "https://fonts.google.com/specimen/Instrument+Sans"),
        .init(name: "Courier Prime",   author: "Quote-Unquote Apps", license: "SIL Open Font License 1.1", url: "https://fonts.google.com/specimen/Courier+Prime"),
    ]

    private let data: [Credit] = [
        .init(name: "Opening Explorer & Masters data", author: "Lichess.org", license: "Public API · CC0 opening database", url: "https://lichess.org"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Acknowledgements").font(AnnFont.serif(20, .semibold)).foregroundColor(DS.ink)
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DS.ink60).frame(width: 26, height: 26).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Tabia is built on open-source work. Thank you to the authors below — their licenses are honored here as required.")
                        .font(AnnFont.voice(14)).foregroundColor(DS.ink60).fixedSize(horizontal: false, vertical: true)

                    section("CHESS ENGINE", software)
                    section("PIECE SETS — from Lichess (lila)", pieces)
                    section("PIECE SETS — other free sources", otherPieces)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("The sets below are licensed CC BY-NC-SA (NonCommercial). They are included because Tabia is distributed free of charge — no ads, in-app purchases, or paid tier. Converted images keep this license and credit their original authors.")
                            .font(AnnFont.voice(12)).foregroundColor(DS.ink60).fixedSize(horizontal: false, vertical: true)
                        section("PIECE SETS — free-app only · CC BY-NC-SA", ncPieces)
                    }

                    section("TYPEFACES", fonts)
                    section("OPENING & REFERENCE DATA", data)

                    Text("Full license texts (GPL-2.0/3.0, AGPL-3.0, Apache-2.0, MIT, CC-BY, CC-BY-SA, CC-BY-NC-SA, CC0, OFL) are bundled inside the app (Tabia.app → Show Package Contents → Contents/Resources). Lichess piece art is from github.com/lichess-org/lila under each set's stated license; other sets are credited above under their own licenses.")
                        .font(AnnFont.mono(9.5)).foregroundColor(DS.ink40).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 480, minHeight: 520)
        .background(DS.paper)
    }

    private func section(_ title: String, _ credits: [Credit]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(AnnFont.label(10, bold: true)).tracking(10 * 0.14).foregroundColor(DS.ink40)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(credits) { c in creditRow(c) }
            }
            .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
        }
    }

    private func creditRow(_ c: Credit) -> some View {
        Button(action: { if let u = URL(string: c.url) { openURL(u) } }) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(AnnFont.serif(14, .medium)).foregroundColor(DS.ink)
                    Text(c.author).font(AnnFont.mono(10)).foregroundColor(DS.ink40)
                }
                Spacer(minLength: 8)
                Text(c.license).font(AnnFont.mono(10, bold: true)).foregroundColor(DS.ink60)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(DS.borderStrong, lineWidth: 1))
                Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundColor(DS.ink40)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
