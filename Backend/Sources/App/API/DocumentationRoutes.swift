import Foundation
import Vapor

/// Serves the OpenAPI document and its rendered reference.
enum DocumentationRoutes {
    /// Redoc, pinned, renders `/openapi.yaml` in the browser.
    static let redocScript = "https://cdn.jsdelivr.net/npm/redoc@2.5.1/bundles/redoc.standalone.js"

    static func register(on routes: any RoutesBuilder) throws {
        guard let url = Bundle.module.url(forResource: "openapi", withExtension: "yaml") else {
            throw Abort(.internalServerError, reason: "openapi.yaml is missing from the app's resources")
        }
        let spec = try String(contentsOf: url, encoding: .utf8)

        routes.get("openapi.yaml") { _ -> Response in
            var headers = HTTPHeaders()
            headers.contentType = HTTPMediaType(type: "application", subType: "yaml")
            return Response(status: .ok, headers: headers, body: .init(string: spec))
        }
        routes.get("docs") { _ -> Response in
            var headers = HTTPHeaders()
            headers.contentType = .html
            return Response(status: .ok, headers: headers, body: .init(string: page))
        }
    }

    private static let page = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>RepoHub API</title>
        </head>
        <body>
          <redoc spec-url="/openapi.yaml"></redoc>
          <script src="\(redocScript)"></script>
        </body>
        </html>
        """
}
