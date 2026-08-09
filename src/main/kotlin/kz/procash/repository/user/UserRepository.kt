package kz.procash.repository.user

import kz.procash.models.user.User
import org.springframework.data.jpa.repository.JpaRepository
import java.util.Optional
import java.util.UUID

interface UserRepository : JpaRepository<User, UUID> {
    fun findByEmailIgnoreCase(email: String): Optional<User>
    fun existsByEmailIgnoreCase(email: String): Boolean
}
