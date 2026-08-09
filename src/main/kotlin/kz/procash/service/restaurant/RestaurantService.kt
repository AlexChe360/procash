package kz.procash.service.restaurant

import kz.procash.models.restaurant.Restaurant
import kz.procash.exception.restaurant.RestaurantNotFoundException
import kz.procash.repository.restaurant.RestaurantRepository
import kz.procash.repository.user.UserRepository
import kz.procash.web.controllers.restaurant.CreateRestaurantForm
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.util.UUID

@Service
class RestaurantService(
    private val restaurantRepository: RestaurantRepository,
    private val userRepository: UserRepository
) {

    @Transactional(readOnly = true)
    fun findAllForUser(email: String): List<Restaurant> {
        val user = findUser(email)

        return restaurantRepository
            .findAllByOwnerIdOrderByCreatedAtDesc(user.id)
    }

    @Transactional(readOnly = true)
    fun countForUser(email: String): Long {
        val user = findUser(email)

        return restaurantRepository.countByOwnerId(user.id)
    }

    @Transactional
    fun create(
        email: String,
        form: CreateRestaurantForm
    ): Restaurant {
        val user = findUser(email)
        val slug = normalizeSlug(form.slug)

        require(
            !restaurantRepository.existsBySlugIgnoreCase(slug)
        ) {
            "Ресторан с таким адресом уже существует"
        }

        val restaurant = Restaurant(
            owner = user,
            name = form.name.trim(),
            slug = slug,
            description = form.description.trim().ifBlank { null },
            phone = form.phone.trim().ifBlank { null },
            city = form.city.trim().ifBlank { null }
        )

        return restaurantRepository.save(restaurant)
    }

    @Transactional(readOnly = true)
    fun slugExists(slug: String): Boolean {
        return restaurantRepository.existsBySlugIgnoreCase(normalizeSlug(slug))
    }

    @Transactional(readOnly = true)
    fun findForUser(
        restaurantId: UUID,
        email: String
    ): Restaurant {
        val user = findUser(email)

        return restaurantRepository
            .findByIdAndOwnerId(restaurantId, user.id) ?: throw RestaurantNotFoundException()
    }


    private fun findUser(email: String) =
        userRepository.findByEmailIgnoreCase(email.trim())
            .orElseThrow {
                IllegalStateException(
                    "Авторизованный пользователь не найден"
                )
            }

    private fun normalizeSlug(slug: String): String {
        return slug
            .trim()
            .lowercase()
    }
}