//
//  couchdb_vapor.swift
//  couchdb-vapor
//
//  Created by Sergey Armodin on 06/03/2019.
//

import Foundation
import NIO
import NIOHTTP1
import AsyncHTTPClient


public class CouchDBClient: NSObject {
	// MARK: - Public properties
	
	/// Flag if did authorize in CouchDB
	var isAuthorized: Bool { authData?.ok ?? false }
	
	// MARK: - Private properties
	
	/// Protocol
	private var couchProtocol: String = "http://"
	/// Host
	private var couchHost: String = "127.0.0.1"
	/// Port
	private var couchPort: Int = 5984
	/// Base URL
	private var couchBaseURL: String = ""
	/// Session cookie for requests that needs authorization
	private var sessionCookie: String?
	/// CouchDB user name
	private var userName: String = ""
	/// CouchDB user password
	private var userPassword: String = ""
	/// Authorization response from CouchDB
	private var authData: CreateSessionResponse?


	// MARK: - Init
	public override init() {
		super.init()
		self.couchBaseURL = self.buildBaseUrl()
	}
	
	public init(couchProtocol: String = "http://", couchHost: String = "127.0.0.1", couchPort: Int = 5984, userName: String = "", userPassword: String = "") {
		self.couchProtocol = couchProtocol
		self.couchHost = couchHost
		self.couchPort = couchPort
		self.userName = userName
		self.userPassword = userPassword
		
		super.init()
		self.couchBaseURL = self.buildBaseUrl()
	}
	
	
	// MARK: - Public methods
	
	/// Get DBs list
	///
	/// - Parameter worker: Worker (EventLoopGroup)
	/// - Returns: Future (EventLoopFuture) with array of strings containing DBs names
	public func getAllDBs(worker: EventLoopGroup) -> EventLoopFuture<[String]?> {
		let httpClient = HTTPClient(eventLoopGroupProvider: .shared(worker))
		defer { try? httpClient.syncShutdown() }
		
		let url = self.couchBaseURL + "/_all_dbs"
		
		do {
			return try authIfNeed(worker: worker)
				.flatMap({ [weak self] (session) -> EventLoopFuture<[String]?> in
					guard let request = try? self?.makeRequest(fromUrl: url, withMethod: .GET) else {
						return worker.next().makeFailedFuture(NSError())
					}
					
					return httpClient.execute(request: request).flatMap { (response) -> EventLoopFuture<[String]?> in
						guard let bytes = response.body else {
							return worker.next().makeSucceededFuture(nil)
						}
						
						let data = Data(buffer: bytes)
						let decoder = JSONDecoder()
						let databasesList = try? decoder.decode([String].self, from: data)
						
						return worker.next().makeSucceededFuture(databasesList)
					}
				})
		} catch {
			return worker.next().makeFailedFuture(error)
		}
	}

	/// Get data from DB
	///
	/// - Parameters:
	///   - dbName: DB name
	///   - uri: uri (view or document id)
	///   - query: requst query
	///   - worker: Worker (EventLoopGroup)
	/// - Returns: Future (EventLoopFuture) with response
	public func get(dbName: String, uri: String, query: [String: Any]? = nil, worker: EventLoopGroup) -> EventLoopFuture<HTTPClient.Response>? {
		let httpClient = HTTPClient(eventLoopGroupProvider: .shared(worker))
		defer { try? httpClient.syncShutdown() }

		let queryString = buildQuery(fromQuery: query)
		let url = self.couchBaseURL + "/" + dbName + "/" + uri + queryString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
		return httpClient.get(url: url)
	}

	/// Update data in DB
	///
	/// - Parameters:
	///   - dbName: DB name
	///   - uri: uri (view or document id)
	///   - body: data which will be in request body
	///   - worker: Worker (EventLoopGroup)
	/// - Returns: Future (EventLoopFuture) with update response (CouchUpdateResponse)
	public func update(dbName: String, uri: String, body: HTTPClient.Body, worker: EventLoopGroup ) -> EventLoopFuture<CouchUpdateResponse>? {
		let httpClient = HTTPClient(eventLoopGroupProvider: .shared(worker))
		defer { try? httpClient.syncShutdown() }

		let url = self.couchBaseURL + "/" + dbName + "/" + uri
		guard var request = try? HTTPClient.Request(url:url, method: .PUT) else {
			return worker.next().makeSucceededFuture(CouchUpdateResponse(ok: false, id: "", rev: ""))
		}
		request.headers.add(name: "Content-Type", value: "application/json")
		request.body = body
		
		return httpClient
			.execute(request: request, deadline: .now() + .seconds(30))
			.flatMap { (response) -> EventLoopFuture<CouchUpdateResponse> in
				guard let bytes = response.body else {
					return worker.next().makeSucceededFuture(CouchUpdateResponse(ok: false, id: "", rev: ""))
				}
				
				let data = Data(buffer: bytes)
				let decoder = JSONDecoder()
				decoder.dateDecodingStrategy = .secondsSince1970
				guard let updateResponse = try? decoder.decode(CouchUpdateResponse.self, from: data) else {
					return worker.next().makeSucceededFuture(CouchUpdateResponse(ok: false, id: "", rev: ""))
				}
				return worker.next().makeSucceededFuture(updateResponse)
		}
	}

	/// Insert document in DB
	///
	/// - Parameters:
	///   - dbName: DB name
	///   - body: data which will be in request body
	///   - worker: Worker (EventLoopGroup)
	/// - Returns: Future (EventLoopFuture) with insert response (CouchUpdateResponse)
	public func insert(dbName: String, body: HTTPClient.Body, worker: EventLoopGroup ) -> EventLoopFuture<CouchUpdateResponse>? {
		let httpClient = HTTPClient(eventLoopGroupProvider: .shared(worker))
		defer { try? httpClient.syncShutdown() }

		let url = self.couchBaseURL + "/" + dbName
		
		guard var request = try? HTTPClient.Request(url:url, method: .POST) else {
			return worker.next().makeSucceededFuture(CouchUpdateResponse(ok: false, id: "", rev: ""))
		}
		request.headers.add(name: "Content-Type", value: "application/json")
		request.body = body
		
		return httpClient
			.execute(request: request, deadline: .now() + .seconds(30))
			.flatMap { (response) -> EventLoopFuture<CouchUpdateResponse> in
				guard let bytes = response.body else {
					return worker.next().makeSucceededFuture(CouchUpdateResponse(ok: false, id: "", rev: ""))
				}
				
				let data = Data(buffer: bytes)
				let decoder = JSONDecoder()
				decoder.dateDecodingStrategy = .secondsSince1970
				guard let updateResponse = try? decoder.decode(CouchUpdateResponse.self, from: data) else {
					return worker.next().makeSucceededFuture(CouchUpdateResponse(ok: false, id: "", rev: ""))
				}
				return worker.next().makeSucceededFuture(updateResponse)
		}
	}

	/// Delete document from DB
	///
	/// - Parameters:
	///   - dbName: DB name
	///   - uri: document uri (usually _id)
	///   - rev: document revision (usually _rev)
	///   - worker: Worker (EventLoopGroup)
	/// - Returns: Future (EventLoopFuture) with delete response (CouchUpdateResponse)
	public func delete(fromDb dbName: String, uri: String, rev: String, worker: EventLoopGroup) -> EventLoopFuture<CouchUpdateResponse>? {
		let httpClient = HTTPClient(eventLoopGroupProvider: .shared(worker))
		defer { try? httpClient.syncShutdown() }

		let queryString = buildQuery(fromQuery: ["rev": rev])
		let url = self.couchBaseURL + "/" + dbName + "/" + uri + queryString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

		return httpClient.delete(url: url).flatMap { (response) -> EventLoopFuture<CouchUpdateResponse> in
			guard let bytes = response.body else {
				return worker.next().makeSucceededFuture(CouchUpdateResponse(ok: false, id: "", rev: ""))
			}
			
			let data = Data(buffer: bytes)
			let decoder = JSONDecoder()
			guard let deleteResponse = try? decoder.decode(CouchUpdateResponse.self, from: data) else {
				return worker.next().makeSucceededFuture(CouchUpdateResponse(ok: false, id: "", rev: ""))
			}
			
			return worker.next().makeSucceededFuture(deleteResponse)
		}
	}
}


// MARK: - Private methods
internal extension CouchDBClient {
	/// Build Base URL
	///
	/// - Returns: Base URL string
	func buildBaseUrl() -> String { "\(self.couchProtocol)\(self.couchHost):\(self.couchPort)" }
	
	/// Build query string
	///
	/// - Parameter query: params dictionary
	/// - Returns: query string
	func buildQuery(fromQuery queryDictionary: [String: Any]?) -> String {
		var queryString = ""
		if let query = queryDictionary {
			queryString = "?" + query.map({ "\($0.key)=\($0.value)" }).joined(separator: "&")
		}
		return queryString
	}
	
	/// Get authorization cookie in didn't yet. This cookie will be added automatically to requests that require authorization
	/// - Parameter worker: Worker (EventLoopGroup)
	/// - Returns: Future (EventLoopFuture) with authorization response (CreateSessionResponse)
	func authIfNeed(worker: EventLoopGroup) throws -> EventLoopFuture<CreateSessionResponse> {
		// already authorized
		if let authData = self.authData {
			return worker.next().makeSucceededFuture(authData)
		}
		
		let httpClient = HTTPClient(eventLoopGroupProvider: .shared(worker))
		defer { try? httpClient.syncShutdown() }
		
		let url = self.couchBaseURL + "/_session"
		
		do {
			var request = try HTTPClient.Request(url:url, method: .POST)
			request.headers.add(name: "Content-Type", value: "application/x-www-form-urlencoded")
			let dataString = "name=\(userName)&password=\(userPassword)"
			request.body = HTTPClient.Body.string(dataString)
			
			return httpClient
				.execute(request: request, deadline: .now() + .seconds(30))
				.flatMapResult { [weak self] (response) -> Result<CreateSessionResponse, Error> in
					guard let bytes = response.body else {
						return Result.failure(NSError())
					}
					
					var cookie = ""
					response.headers.forEach { (header: (name: String, value: String)) in
						if header.name == "Set-Cookie" {
							cookie = header.value
						}
					}
					self?.sessionCookie = cookie
					
					guard let authData = try? JSONDecoder().decode(CreateSessionResponse.self, from: bytes) else {
						return Result.failure(NSError())
					}
					self?.authData = authData
					return Result.success(authData)
			}
		} catch {
			return worker.next().makeFailedFuture(error)
		}
	}
	
	/// Make HTTP request from url string
	/// - Parameters:
	///   - url: url string
	///   - method: HTTP method
	/// - Returns: request
	func makeRequest(fromUrl url: String, withMethod method: HTTPMethod) throws -> HTTPClient.Request  {
		var headers = HTTPHeaders()
		if let cookie = sessionCookie {
			headers = HTTPHeaders([("Cookie", cookie)])
		}
		return try HTTPClient.Request(
			url: url,
			method: method,
			headers: headers,
			body: nil
		)
	}
}
