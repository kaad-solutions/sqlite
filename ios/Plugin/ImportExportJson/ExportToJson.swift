//
//  ExportToJson.swift
//  Plugin
//
//  Created by  Quéau Jean Pierre on 18/12/2020.
//  Copyright © 2020 Max Lynch. All rights reserved.
//

import Foundation
import SQLCipher

// swiftlint:disable type_body_length
// swiftlint:disable file_length
enum ExportToJsonError: Error {
    case createExportObject(message: String)
    case getTablesFull(message: String)
    case getTablesPartial(message: String)
    case getSchemaIndexes(message: String)
    case getValues(message: String)
    case createIndexes(message: String)
    case createSchema(message: String)
    case createValues(message: String)
    case getPartialModeData(message: String)
    case getTablesModified(message: String)
    case getSyncDate(message: String)
    case createRowValues(message: String)
}
class ExportToJson {

    // MARK: - ExportToJson - CreateExportObject

    // swiftlint:disable function_body_length
    // swiftlint:disable cyclomatic_complexity
    class func createExportObject(mDB: Database,
                                  data: [String: Any])
                                            throws -> [String: Any] {
        var retObj: [String: Any] = [:]
        let message = "exportToJson: createExportObject miss data: "
        guard let expMode = data["expMode"] as? String else {
            throw ExportToJsonError.createExportObject(
                message: message + "expMode")
        }
        guard let dbName = data["dbName"] as? String else {
            throw ExportToJsonError.createExportObject(
                message: message + "dbName")
        }
        guard let encrypted = data["encrypted"] as? Bool else {
            throw ExportToJsonError.createExportObject(
                message: message + "encrypted")
        }
        guard let dbVersion = data["version"] as? Int else {
            throw ExportToJsonError.createExportObject(
                message: message + "version")
        }

        var tables: [[String: Any]] = []

        // get the table's name
        var query: String = "SELECT name,sql FROM sqlite_master WHERE "
        query.append("type = 'table' AND name NOT LIKE 'sqlite_%' ")
        query.append("AND name NOT LIKE 'sync_table';")
        do {
            let resTables =  try UtilsSQLCipher.querySQL(
                                    mDB: mDB, sql: query, values: [])
            if resTables.count > 0 {
                switch expMode {
                case "partial" :
                    tables = try ExportToJson
                        .getTablesPartial(mDB: mDB,
                                          resTables: resTables)
                case "full":
                    tables = try ExportToJson.getTablesFull(mDB: mDB,
                        resTables: resTables)

                default:
                    throw ExportToJsonError.createExportObject(
                        message: "expMode \(expMode) not defined")
                }
            }
        } catch UtilsSQLCipherError.querySQL(let message) {
            throw ExportToJsonError.createExportObject(
                message: "Error get table's names failed : \(message)")
        } catch ExportToJsonError.getTablesFull(let message) {
            throw ExportToJsonError.createExportObject(
                message: "Error get tables 'Full' failed : \(message)")
        } catch ExportToJsonError.getTablesPartial(let message) {
                   throw ExportToJsonError.createExportObject(
                        message: "Error get tables 'Partial' failed :" +
                        " \(message)")
        }
        if tables.count > 0 {
            retObj["database"] = dbName.dropLast(9)
            retObj["version"] = dbVersion
            retObj["encrypted"] = encrypted
            retObj["mode"] = expMode
            retObj["tables"] = tables
        }

        return retObj
    }
    // swiftlint:enable cyclomatic_complexity
    // swiftlint:enable function_body_length

    // MARK: - ExportToJson - GetSchemaIndexes

    class func getSchemaIndexes(mDB: Database,
                                stmt: String, table: [String: Any] )
                                            throws -> [String: Any] {
        var retTable: [String: Any] = table
        var isSchema: Bool  = false
        var isIndexes: Bool = false
        do {
            // create schema
            let schema: [[String: String]] = try
                ExportToJson.createSchema(stmt: stmt)
            if schema.count > 0 {
                isSchema = try UtilsJson.validateSchema(schema: schema)
                if isSchema {retTable["schema"] = schema}
            }
            // create indexes
            guard let tableName: String = table["name"] as? String
            else {
                var message: String = "Error getSchemaIndexes: did not"
                message.append("find table name")
                throw ExportToJsonError.getSchemaIndexes(
                    message: message)
            }
            let indexes: [[String: String]] = try
                ExportToJson.createIndexes(mDB: mDB,
                                           tableName: tableName)
            if indexes.count > 0 {
                isIndexes = try UtilsJson.validateIndexes(
                    indexes: indexes)
                if isIndexes {retTable["indexes"] = indexes}
            }
            let retObj: [String: Any] = ["isSchema": isSchema,
                                         "isIndexes": isIndexes,
                                         "table": retTable]
            return retObj
        } catch ExportToJsonError.createSchema(let message) {
            throw ExportToJsonError.getSchemaIndexes(message: message)
        } catch UtilsJsonError.validateSchema(let message) {
            throw ExportToJsonError.getSchemaIndexes(message: message)
        } catch ExportToJsonError.createIndexes(let message) {
            throw ExportToJsonError.getSchemaIndexes(message: message)
        } catch UtilsJsonError.validateIndexes(let message) {
            throw ExportToJsonError.getSchemaIndexes(message: message)
        }
    }

    // MARK: - ExportToJson - GetValues

    class func getValues(mDB: Database, stmt: String,
                         table: [String: Any] )
                                            throws -> [String: Any] {
        var retTable: [String: Any] = table
        var isValues: Bool  = false
        do {
            guard let tableName: String = table["name"] as? String
            else {
                var message: String = "Error getSchemaIndexes: did "
                message.append("not find table name")
                throw ExportToJsonError.getValues(message: message)
            }
            let jsonNamesTypes: JsonNamesTypes = try UtilsJson
                    .getTableColumnNamesTypes(mDB: mDB,
                                              tableName: tableName)
            let rowNames = jsonNamesTypes.names
            let rowTypes = jsonNamesTypes.types

            // create the table data
            let values: [[Any]] = try ExportToJson
                .createValues(mDB: mDB, query: stmt, names: rowNames,
                              types: rowTypes)
            if values.count > 0 {
                retTable["values"] = values
                isValues = true
            }
            let retObj: [String: Any] = ["isValues": isValues,
                                         "table": retTable]
            return retObj
        } catch UtilsJsonError.getTableColumnNamesTypes(let message) {
            throw ExportToJsonError.getValues(message: message)
        } catch ExportToJsonError.createValues(let message) {
            throw ExportToJsonError.getValues(message: message)
        }
    }

    // MARK: - ExportToJson - GetTablesFull

    // swiftlint:disable cyclomatic_complexity
    // swiftlint:disable function_body_length
    class func getTablesFull(mDB: Database,
                             resTables: [[String: Any]])
                                            throws -> [[String: Any]] {
        var tables: [[String: Any]] = []
        for rTable in resTables {
            guard let tableName: String = rTable["name"] as? String
            else {
                throw ExportToJsonError.getTablesFull(
                    message: "Error did not find table name")
            }
            guard let sqlStmt: String = rTable["sql"] as? String else {
                throw ExportToJsonError.getTablesFull(
                    message: "Error did not find sql statement")
            }
            var table: [String: Any] = [:]
            table["name"] = tableName
            var result: [String: Any] = [:]
            do {
                // create schema and indexes
                result = try ExportToJson
                        .getSchemaIndexes(mDB: mDB,
                                          stmt: sqlStmt, table: table)
                guard let isSchema: Bool = result["isSchema"] as? Bool
                else {
                    throw ExportToJsonError.getTablesFull(
                        message: "Error did not find isSchema")
                }
                // this seems not correct as it can be case without index
                guard let isIndexes: Bool = result["isIndexes"] as? Bool
                else {
                    throw ExportToJsonError.getTablesFull(
                        message: "Error did not find isIndexes")
                }
                guard let retTable: [String: Any] =
                        result["table"] as? [String: Any] else {
                    throw ExportToJsonError.getTablesFull(
                        message: "Error did not find table")
                }
                table = retTable
                // create the table data
                let query: String = "SELECT * FROM \(tableName);"
                result = try ExportToJson
                            .getValues(mDB: mDB, stmt: query,
                                       table: table)
                guard let isValues: Bool = result["isValues"] as? Bool
                else {
                    throw ExportToJsonError.getTablesFull(
                        message: "Error did not find isValues")
                }
                guard let retTable1: [String: Any] = result["table"]
                        as? [String: Any] else {
                    throw ExportToJsonError.getTablesFull(
                        message: "Error did not find table")
                }
                table = retTable1
                // check the table object validity
                var tableKeys: [String] = []
                tableKeys.append(contentsOf: table.keys)

                if tableKeys.count <= 1 ||
                        (!isSchema && !isIndexes && !isValues) {
                    throw ExportToJsonError.getTablesFull(
                        message: "Error table \(tableName) is not a jsonTable")
                }
                tables.append(table)
            } catch ExportToJsonError.getSchemaIndexes(let message) {
                throw ExportToJsonError.getTablesFull(
                    message: message)
            } catch ExportToJsonError.getValues(let message) {
                throw ExportToJsonError.getTablesFull(
                    message: message)
            }
        }

        return tables
    }
    // swiftlint:enable function_body_length
    // swiftlint:enable cyclomatic_complexity

    // MARK: - ExportToJson - GetTablesPartial

    // swiftlint:disable function_body_length
    // swiftlint:disable cyclomatic_complexity
    class func getTablesPartial(mDB: Database,
                                resTables: [[String: Any]])
                                        throws -> [[String: Any]] {
        var tables: [[String: Any]] = []
        var syncDate: Int64 = 0
        var modTables: [String: String] = [:]
        var modTablesKeys: [String] = []
        var result: [String: Any] = [:]
        var isSchema: Bool = false
        var isIndexes: Bool = false
        do {
            // Get the syncDate and the Modified Tables
            let partialModeData: [String: Any] = try
                ExportToJson.getPartialModeData(mDB: mDB,
                                                tables: resTables)
            guard let sDate = partialModeData["syncDate"] as? Int64
            else {
                let message: String = "Error cannot find syncDate"
                throw ExportToJsonError.getTablesPartial(
                    message: message)
            }
            guard let mTables = partialModeData["modTables"] as?
                    [String: String] else {
                let message: String = "Error cannot find modTables"
                throw ExportToJsonError.getTablesPartial(
                    message: message)
            }
            syncDate = sDate
            modTables = mTables
            modTablesKeys.append(contentsOf: modTables.keys)

            for rTable in resTables {
                guard let tableName: String = rTable["name"] as? String
                else {
                    throw ExportToJsonError.getTablesPartial(
                        message: "Error did not find table name")
                }
                guard let sqlStmt: String = rTable["sql"] as? String
                else {
                    throw ExportToJsonError.getTablesPartial(
                        message: "Error did not find sql statement")
                }
                if modTablesKeys.count == 0 ||
                        !modTablesKeys.contains(tableName) ||
                        modTables[tableName] == "No" {
                    continue
                }
                var table: [String: Any] = [:]
                table["name"] = tableName
                if modTables[tableName] == "Create" {
                    // create schema and indexes
                    result = try ExportToJson
                        .getSchemaIndexes(mDB: mDB, stmt: sqlStmt,
                                          table: table)
                    guard let isSch: Bool = result["isSchema"] as? Bool
                    else {
                        throw ExportToJsonError.getTablesFull(
                            message: "Error did not find isSchema")
                    }
                    guard let isIdxes: Bool = result["isIndexes"] as?
                            Bool else {
                        throw ExportToJsonError.getTablesFull(
                            message: "Error did not find isIndexes")
                    }
                    guard let retTable: [String: Any] = result["table"]
                            as? [String: Any] else {
                        throw ExportToJsonError.getTablesFull(
                            message: "Error did not find table")
                    }
                    isSchema = isSch
                    isIndexes = isIdxes
                    table = retTable
                }
                // create table data
                let query: String = modTables[tableName] == "Create"
                    ? "SELECT * FROM \(tableName);"
                    : "SELECT * FROM \(tableName) WHERE last_modified" +
                    " > \(syncDate);"
                result = try ExportToJson
                                    .getValues(mDB: mDB, stmt: query,
                                               table: table)
                guard let isValues: Bool = result["isValues"] as? Bool
                else {
                    throw ExportToJsonError.getTablesFull(
                        message: "Error did not find isValues")
                }
                guard let retTable1: [String: Any] = result["table"]
                                                as? [String: Any] else {
                    throw ExportToJsonError.getTablesFull(
                                message: "Error did not find table")
                }
                table = retTable1
                // check the table object validity
                var tableKeys: [String] = []
                tableKeys.append(contentsOf: table.keys)

                if tableKeys.count <= 1 ||
                        (!isSchema && !isIndexes && !isValues) {
                    throw ExportToJsonError.getTablesPartial(
                            message: "Error table \(tableName) is not a jsonTable")
                }
                tables.append(table)
            }
        } catch ExportToJsonError.getSchemaIndexes(let message) {
            throw ExportToJsonError.getTablesPartial(message: message)
        } catch ExportToJsonError.getValues(let message) {
            throw ExportToJsonError.getTablesPartial(message: message)
        }
        return tables
    }
    // swiftlint:enable cyclomatic_complexity
    // swiftlint:enable function_body_length

    // MARK: - ExportToJson - GetPartialModeData

    class func getPartialModeData(mDB: Database,
                                  tables: [[String: Any]])
                                        throws -> [String: Any] {
        var retData: [String: Any] = [:]
        var syncDate: Int64 = 0
        var modTables: [String: String] = [:]

        // get the sync date if expMode = "partial"
        syncDate = try ExportToJson.getSyncDate(mDB: mDB)
        if syncDate == -1 {
            throw ExportToJsonError.getPartialModeData(
                message: "Error did not find a sync_date")
        }
        do {
            // get the tables which have been updated 
            // since last synchronization
            modTables = try ExportToJson
                    .getTablesModified(mDB: mDB, tables: tables,
                                       syncDate: syncDate)
            retData = ["syncDate": syncDate, "modTables": modTables]
        } catch ExportToJsonError.getTablesModified(let message) {
            throw ExportToJsonError
                                .getPartialModeData(message: message)
        }
        return retData
    }

    // MARK: - ExportToJson - GetSyncDate

    class func getSyncDate(mDB: Database) throws -> Int64 {
        var ret: Int64 = -1
        let query: String = "SELECT sync_date FROM sync_table;"
        do {
            let resSyncDate =  try UtilsSQLCipher.querySQL(
                                mDB: mDB, sql: query, values: [])
            if resSyncDate.count > 0 {
                guard let res: Int64 = resSyncDate[0]["sync_date"] as?
                                        Int64 else {
                    throw ExportToJsonError.getSyncDate(
                                message: "Error get sync date failed")
                }
                if res > 0 {ret = res}
            }
        } catch UtilsSQLCipherError.querySQL(let message) {
            throw ExportToJsonError.getSyncDate(
                    message: "Error get sync date failed : \(message)")
        }
        return ret
    }

    // MARK: - ExportToJson - GetTablesModified

    // swiftlint:disable function_body_length
    class func getTablesModified(mDB: Database,
                                 tables: [[String: Any]],
                                 syncDate: Int64)
                                        throws -> [String: String] {
        var retObj: [String: String] = [:]
        if tables.count > 0 {
            for ipos in 0..<tables.count {
                var mode: String
                // get total count of the table
                guard let tableName: String = tables[ipos]["name"] as?
                                                String else {
                    var msg: String = "Error get modified tables "
                    msg.append("failed: No statement given")
                    throw ExportToJsonError.getTablesModified(
                        message: msg)
                }
                var query: String = "SELECT count(*) AS count FROM "
                query.append("\(tableName);")
                do {
                    var resQuery =  try UtilsSQLCipher.querySQL(
                                    mDB: mDB, sql: query, values: [])
                    if resQuery.count != 1 {
                        break
                    } else {
                        guard let totalCount: Int64 =
                            resQuery[0]["count"]  as? Int64 else {
                            var msg: String = "Error get modified "
                            msg.append("tables failed: totalCount not")
                            msg.append(" defined")
                            throw ExportToJsonError
                                    .getTablesModified(message: msg)
                        }
                        query = "SELECT count(*) AS count FROM \(tableName) "
                        query.append("WHERE last_modified > ")
                        query.append("\(syncDate);")
                        resQuery =  try UtilsSQLCipher.querySQL(
                                    mDB: mDB, sql: query, values: [])
                        if resQuery.count != 1 {
                            break
                        } else {
                            guard let totalModifiedCount: Int64 =
                                    (resQuery[0]["count"]  as?
                                                    Int64) else {
                                var msg: String = "Error get modified "
                                msg.append("tables failed:")
                                msg.append("totalModifiedCount not ")
                                msg.append("defined")
                                throw ExportToJsonError
                                    .getTablesModified(message: msg)
                            }
                            if totalModifiedCount == 0 {
                                mode = "No"
                            } else if totalCount == totalModifiedCount {
                                mode = "Create"
                            } else {
                                mode = "Modified"
                            }
                            retObj[tableName] = mode
                        }
                    }
                } catch UtilsSQLCipherError.querySQL(let message) {
                    var msg: String = "Error get modified tables "
                    msg.append("failed : \(message)")
                    throw ExportToJsonError.getTablesModified(
                        message: msg)
                }
            }
        }
        return retObj
    }
    // swiftlint:enable function_body_length

    // MARK: - ExportToJson - CreateSchema

    // swiftlint:disable function_body_length
    // swiftlint:disable cyclomatic_complexity
    class func createSchema(stmt: String) throws -> [[String: String]] {
        var retSchema: [[String: String]] = []
        // get the sqlStmt between the parenthesis sqlStmt
        if let openPar = stmt.firstIndex(of: "(") {
            if let closePar = stmt.lastIndex(of: ")") {
                let sqlStmt: String = String(
                        stmt[stmt.index(after: openPar)..<closePar])
                var isStrfTime: Bool = false
                if sqlStmt.contains("strftime") {
                    isStrfTime = true
                }
                var sch: [String] = sqlStmt.components(separatedBy: ",")
                if isStrfTime {
                    var nSch: [String] = []
                    var irem: Int = -1
                    for ipos in 0..<sch.count {
                        if sch[ipos].contains("strftime") {
                            let merge: String = sch[ipos + 1]
                            nSch.append("\(sch[ipos]),\(merge)")
                            irem = ipos + 1
                        } else {
                            nSch.append(sch[ipos])
                        }
                    }
                    if irem != -1 {
                        nSch.remove(at: irem)
                    }
                    sch = nSch
                }
                for ipos in 0..<sch.count {
                    let rstr: String = sch[ipos]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    var row = rstr.split(separator: " ", maxSplits: 1)
                    if  row.count == 2 {
                        var columns: [String: String] = [:]
                        if String(row[0]).uppercased() != "FOREIGN" {
                            columns["column"] =  String(row[0])
                        } else {
                            guard let oPar = rstr.firstIndex(of: "(")
                                    else {
                                var msg: String = "Create Schema "
                                msg.append("FOREIGN KEYS no '('")
                                throw ExportToJsonError
                                        .createSchema(message: msg)
                            }
                            guard let cPar = rstr.firstIndex(of: ")")
                                    else {
                                var msg: String = "Create Schema "
                                msg.append("FOREIGN KEYS no ')'")
                                throw ExportToJsonError
                                        .createSchema(message: msg)
                            }
                            row[0] = rstr[rstr.index(
                                            after: oPar)..<cPar]
                            row[1] = rstr[rstr.index(
                                    cPar, offsetBy: 2)..<rstr.endIndex]
                            print("row[0] \(row[0]) row[1] \(row[1]) ")
                            columns["foreignkey"] = String(row[0])
                        }
                        columns["value"] = String(row[1])
                        retSchema.append(columns)
                    } else {
                        throw ExportToJsonError.createSchema(
                            message: "Query result not well formatted")
                    }
                }
            } else {
                throw ExportToJsonError.createSchema(
                            message: "No ')' in the query result")
            }
        } else {
            throw ExportToJsonError.createSchema(
                        message: "No '(' in the query result")
        }
        return retSchema
    }
    // swiftlint:enable cyclomatic_complexity
    // swiftlint:enable function_body_length

    // MARK: - ExportToJson - CreateIndexes

    // swiftlint:disable function_body_length
    class func createIndexes(mDB: Database, tableName: String)
                                    throws -> [[String: String]] {
        var retIndexes: [[String: String]] = []
        var query = "SELECT name,tbl_name,sql FROM sqlite_master WHERE "
        query.append("type = 'index' AND tbl_name = '\(tableName)' ")
        query.append("AND sql NOTNULL;")
        do {
            let resIndexes =  try UtilsSQLCipher.querySQL(
                                mDB: mDB, sql: query, values: [])
            if resIndexes.count > 0 {
                for ipos in 0..<resIndexes.count {
                    var row: [String: String] = [:]
                    let keys: [String] = Array(resIndexes[ipos].keys)
                    if keys.count == 3 {
                        guard let tblName =
                                resIndexes[ipos]["tbl_name"] as? String
                                        else {
                            var msg: String = "Error indexes tbl_name "
                            msg.append("not found")
                            throw ExportToJsonError
                                    .createIndexes(message: msg)
                        }
                        if tblName == tableName {
                            guard let sql: String =
                                    resIndexes[ipos]["sql"] as? String
                                        else {
                                var msg: String = "Error indexes sql "
                                msg.append("not found")
                                throw ExportToJsonError
                                    .createIndexes(message: msg)
                            }
                            guard let name = resIndexes[ipos]["name"]
                                    as? String else {
                                var msg: String = "Error indexes name "
                                msg.append("not found")
                                 throw ExportToJsonError
                                        .createIndexes(message: msg)
                            }
                            guard let oPar = sql.lastIndex(of: "(")
                                        else {
                                var msg: String = "Create Indexes no "
                                msg.append("'('")
                                throw ExportToJsonError
                                        .createIndexes(message: msg)
                            }
                            guard let cPar = sql.lastIndex(of: ")")
                                        else {
                                var msg: String = "Create Indexes no "
                                msg.append("')'")
                                throw ExportToJsonError
                                        .createIndexes(message: msg)
                            }
                            row["column"] = String(sql[sql.index(
                                                after: oPar)..<cPar])
                            row["name"] = name
                            retIndexes.append(row)
                        } else {
                            var msg: String = "Error indexes table name"
                            msg.append(" doesn't match")
                            throw ExportToJsonError
                                    .createIndexes(message: msg)
                        }
                    } else {
                        throw ExportToJsonError.createIndexes(
                            message: "Error No indexes key found ")
                    }
                }
            }
        } catch UtilsSQLCipherError.querySQL(let message) {
            throw ExportToJsonError.createIndexes(
                message: "Error query indexes failed : \(message)")
        }

        return retIndexes
    }
    // swiftlint:enable function_body_length

    // MARK: - ExportToJson - CreateValues

    class func createValues(mDB: Database,
                            query: String, names: [String],
                            types: [String]) throws -> [[Any]] {

        var retValues: [[Any]] = []
        do {
            let resValues =  try UtilsSQLCipher.querySQL(
                                mDB: mDB, sql: query, values: [])
            if resValues.count > 0 {
                for ipos in 0..<resValues.count {
                    var row: [Any] = []
                    do {
                        row = try ExportToJson.createRowValues(
                            values: resValues, pos: ipos, names: names,
                            types: types)
                    } catch ExportToJsonError
                                        .createRowValues(let message) {
                        var msg: String = "Error create row values "
                        msg.append("failed : \(message)")
                        throw ExportToJsonError.createValues(
                            message: msg)
                    }
                    retValues.append(row)
                }
            }
        } catch UtilsSQLCipherError.querySQL(let message) {
            throw ExportToJsonError.createValues(
                message: "Error query values failed : \(message)")
        }

        return retValues
    }

    // MARK: - ExportToJson - CreateRowValues

    class func createRowValues(values: [[String: Any]], pos: Int,
                               names: [String],
                               types: [String] ) throws -> [Any] {
        var row: [Any] = []
        for jpos in 0..<names.count {
            if types[jpos] == "INTEGER" {
                if values[pos][names[jpos]] is String {
                    guard let val = values[pos][names[jpos]] as? String
                                else {
                        throw ExportToJsonError.createValues(
                            message: "Error value must be String")
                    }
                    row.append(val)
                } else {
                    guard let val = values[pos][names[jpos]] as? Int64
                                else {
                        throw ExportToJsonError.createValues(
                            message: "Error value must be String")
                    }
                    row.append(val)
                }
            } else if types[jpos] == "REAL" {
                if values[pos][names[jpos]] is String {
                    guard let val = values[pos][names[jpos]] as? String
                                else {
                        throw ExportToJsonError.createValues(
                            message: "Error value must be String")
                    }
                    row.append(val)
                } else {
                    guard let val = values[pos][names[jpos]] as? Double
                                else {
                        throw ExportToJsonError.createValues(
                            message: "Error value must be Double")
                    }
                    row.append(val)
                }
            } else {
                guard let val = values[pos][names[jpos]] as? String
                            else {
                    throw ExportToJsonError.createValues(
                        message: "Error value must be String")
                }
                row.append(val)
            }
        }
        return row
    }
}
// swiftlint:enable type_body_length
// swiftlint:enable file_length
