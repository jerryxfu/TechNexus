package net.jerryxf.technexus.server

import net.jerryxf.technexus.shared.Battery
import net.jerryxf.technexus.shared.BatteryCycle
import org.jetbrains.exposed.v1.core.dao.id.UIntIdTable
import org.jetbrains.exposed.v1.core.eq
import org.jetbrains.exposed.v1.datetime.timestamp
import org.jetbrains.exposed.v1.jdbc.deleteWhere
import org.jetbrains.exposed.v1.jdbc.SchemaUtils
import org.jetbrains.exposed.v1.jdbc.insert
import org.jetbrains.exposed.v1.jdbc.selectAll
import org.jetbrains.exposed.v1.jdbc.transactions.suspendTransaction
import org.jetbrains.exposed.v1.jdbc.update

internal object Batteries : UIntIdTable() {
    val name = varchar("name", 30)
    val type = varchar("type", 20)
    val year = ubyte("year")
}

internal object BatteryCycles : UIntIdTable() {
    val batteryId = reference("battery_id", Batteries.id)
    val startTime = timestamp("start_time")
    val endTime = timestamp("end_time")
}

/**
 * Creates any tables that don't exist yet.
 *
 * Exposed's `Database.connect` opens a connection and nothing more.
 * It does not look at the table objects above, and it never issues DDL. Against a fresh
 * database that produced `relation "batteries" does not exist` on every
 * /batteries call, because the schema only ever existed in Kotlin.
 *
 * Safe to run on every boot: `create` is a no-op for tables that already exist.
 * It does not alter existing tables, so a column added here still needs a migration.
 */
suspend fun createSchema() = suspendTransaction {
    SchemaUtils.create(Batteries, BatteryCycles)
}

suspend fun createBattery(item: Battery): UInt = suspendTransaction {
    return@suspendTransaction Batteries.insert {
        it[Batteries.name] = item.name
        it[Batteries.type] = item.type
        it[Batteries.year] = item.year
    }[Batteries.id].value
}

suspend fun getBattery(id: UInt): Battery? = suspendTransaction {
    Batteries.selectAll()
        .where { Batteries.id eq id }
        .map {
            Battery(
                it[Batteries.id].value,
                it[Batteries.name],
                it[Batteries.type],
                it[Batteries.year]
            )
        }
        .singleOrNull()
}

suspend fun getBatteries(): List<Battery> = suspendTransaction {
    Batteries.selectAll().map {
        Battery(
            it[Batteries.id].value,
            it[Batteries.name],
            it[Batteries.type],
            it[Batteries.year]
        )
    }
}

suspend fun updateBattery(item: Battery): Boolean = suspendTransaction {
    val updatedRows = Batteries.update({ Batteries.id eq item.id }) {
        it[Batteries.name] = item.name
        it[Batteries.type] = item.type
        it[Batteries.year] = item.year
    }
    updatedRows > 0
}

suspend fun deleteBattery(id: UInt) = suspendTransaction {
    Batteries.deleteWhere { Batteries.id eq id }
}

suspend fun createCycle(item: BatteryCycle): UInt = suspendTransaction {
    BatteryCycles.insert {
        it[BatteryCycles.batteryId] = item.batteryId
        it[BatteryCycles.startTime] = item.startTime
        it[BatteryCycles.endTime] = item.endTime
    }[BatteryCycles.id].value
}

suspend fun getCycle(id: UInt): BatteryCycle? = suspendTransaction {
    BatteryCycles.selectAll()
        .where { BatteryCycles.id eq id }
        .map {
            BatteryCycle(
                it[BatteryCycles.id].value,
                it[BatteryCycles.batteryId].value,
                it[BatteryCycles.startTime],
                it[BatteryCycles.endTime]
            )
        }
        .singleOrNull()
}

suspend fun getCycles(): List<BatteryCycle> = suspendTransaction {
    BatteryCycles.selectAll().map {
        BatteryCycle(
            it[BatteryCycles.id].value,
            it[BatteryCycles.batteryId].value,
            it[BatteryCycles.startTime],
            it[BatteryCycles.endTime]
        )
    }
}

/**
 * Only updates times (not battery)
 * use updateBattery for that
 */
suspend fun updateCycle(item: BatteryCycle): Boolean = suspendTransaction {
    BatteryCycles.update({ BatteryCycles.id eq item.id }) {
        it[BatteryCycles.startTime] = item.startTime
        it[BatteryCycles.endTime] = item.endTime
    } > 0
}

suspend fun deleteCycle(id: UInt) = suspendTransaction {
    BatteryCycles.deleteWhere { BatteryCycles.id eq id }
}
