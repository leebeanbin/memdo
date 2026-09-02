import XCTest
@testable import Memdo

@MainActor
final class AppNoticeCenterTests: XCTestCase {
    func testErrorAndSuccessSetCurrentWithTheExpectedKind() {
        let center = AppNoticeCenter()

        center.error("문제가 발생했어요.")
        XCTAssertEqual(center.current?.kind, .error)
        XCTAssertEqual(center.current?.message, "문제가 발생했어요.")

        center.success("저장했어요.")
        XCTAssertEqual(center.current?.kind, .success)
        XCTAssertEqual(center.current?.message, "저장했어요.")
    }

    func testDismissClearsCurrent() {
        let center = AppNoticeCenter()
        center.error("문제가 발생했어요.")
        center.dismiss()
        XCTAssertNil(center.current)
    }

    /// Mirrors the toast's auto-dismiss race guard: a stale timer from an
    /// older notice must not clear a newer one that has already replaced it.
    func testDismissIfOnlyClearsWhenIDStillMatchesCurrent() {
        let center = AppNoticeCenter()
        center.error("첫 번째")
        let staleID = center.current!.id

        center.error("두 번째") // replaces the first notice before its own timer fires

        center.dismiss(if: staleID)
        XCTAssertEqual(center.current?.message, "두 번째", "a stale id must not clear a newer notice")

        center.dismiss(if: center.current!.id)
        XCTAssertNil(center.current, "a matching id must clear the current notice")
    }
}
