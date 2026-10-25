import REPickShared
import SwiftUI

struct ReportUsagiView: View {
    let reaction: HealthReportReaction?

    var body: some View {
        MapUsagiView(heading: 180, motion: .idle,
                     accessibilityIdentifier: "reports.usagi.scene", reportReaction: reaction ?? .curious)
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityIdentifier("reports.usagi")
    }

    private var accessibilityLabel: String {
        switch reaction {
        case .celebrate: String(localized: "두 팔을 들어 기뻐하는 3D 우사기")
        case .encourage: String(localized: "한 팔을 들어 응원하는 3D 우사기")
        case .rest: String(localized: "편안히 쉬는 3D 우사기")
        case .curious: String(localized: "고개를 기울여 살펴보는 3D 우사기")
        case nil: String(localized: "리포트와 함께 보는 3D 우사기")
        }
    }

    private var accessibilityValue: String {
        switch reaction {
        case .celebrate: String(localized: "축하")
        case .encourage: String(localized: "응원")
        case .rest: String(localized: "휴식")
        case .curious: String(localized: "살펴보기")
        case nil: String(localized: "기본 모습")
        }
    }
}

#Preview {
    ScrollView {
        VStack {
            ReportUsagiView(reaction: .celebrate)
            ReportUsagiView(reaction: .encourage)
            ReportUsagiView(reaction: .rest)
            ReportUsagiView(reaction: .curious)
        }
    }
    .background(Color.repickCream)
}
