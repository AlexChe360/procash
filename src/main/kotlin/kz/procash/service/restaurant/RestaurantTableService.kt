package kz.procash.service.restaurant

import kz.procash.models.restaurant.RestaurantTable
import kz.procash.repository.restaurant.RestaurantTableRepository
import kz.procash.web.controllers.restaurant.CreateRestaurantTableForm
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.util.UUID

@Service
class RestaurantTableService(
    private val tableRepository: RestaurantTableRepository,
    private val restaurantService: RestaurantService
) {
    @Transactional(readOnly = true)
    fun findAllForUser(
        restaurantId: UUID,
        email: String
    ): List<RestaurantTable> {
        restaurantService.findForUser(
            restaurantId = restaurantId,
            email = email
        )

        return tableRepository
            .findAllByRestaurantIdOrderByTableNumberAsc(
                restaurantId
            )
    }

    @Transactional(readOnly = true)
    fun countForUser(
        restaurantId: UUID,
        email: String
    ): Long {
        restaurantService.findForUser(
            restaurantId = restaurantId,
            email = email
        )

        return tableRepository.countByRestaurantId(
            restaurantId
        )
    }

    @Transactional(readOnly = true)
    fun tableNumberExists(
        restaurantId: UUID,
        email: String,
        tableNumber: String
    ): Boolean {
        restaurantService.findForUser(
            restaurantId = restaurantId,
            email = email
        )

        return tableRepository
            .existsByRestaurantIdAndTableNumberIgnoreCase(
                restaurantId,
                normalizeTableNumber(tableNumber)
            )
    }

    @Transactional
    fun create(
        restaurantId: UUID,
        email: String,
        form: CreateRestaurantTableForm
    ): RestaurantTable {
        val restaurant = restaurantService.findForUser(
            restaurantId = restaurantId,
            email = email
        )

        val tableNumber =
            normalizeTableNumber(form.tableNumber)

        require(
            !tableRepository
                .existsByRestaurantIdAndTableNumberIgnoreCase(
                    restaurantId,
                    tableNumber
                )
        ) {
            "Стол с таким номером уже существует"
        }

        val table = RestaurantTable(
            restaurant = restaurant,
            tableNumber = tableNumber,
            displayName = form.displayName
                .trim()
                .ifBlank { null },
            qrToken = UUID.randomUUID(),
            active = true
        )

        return tableRepository.save(table)
    }

    @Transactional(readOnly = true)
    fun findForUser(
        restaurantId: UUID,
        tableId: UUID,
        email: String
    ): RestaurantTable {
        restaurantService.findForUser(
            restaurantId = restaurantId,
            email = email
        )

        return tableRepository
            .findByIdAndRestaurantId(
                tableId,
                restaurantId
            )
            ?: throw IllegalStateException(
                "Стол не найден"
            )
    }

    @Transactional(readOnly = true)
    fun findActiveByQrToken(
        qrToken: UUID
    ): RestaurantTable {
        return tableRepository.findByQrTokenAndActiveTrue(qrToken)
            ?: throw IllegalStateException("QR-код недействителен или стол отключен")
    }

    private fun normalizeTableNumber(
        value: String
    ): String {
        return value.trim()
    }
}