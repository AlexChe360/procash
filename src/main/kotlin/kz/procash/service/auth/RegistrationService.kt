package kz.procash.service.auth

import kz.procash.models.user.User
import kz.procash.repository.user.UserRepository
import kz.procash.models.user.UserRole
import kz.procash.web.controllers.auth.RegistrationForm
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

@Service
class RegistrationService(
    private val userRepository: UserRepository,
    private val passwordEncoder: PasswordEncoder
) {
    fun emailExists(email: String): Boolean {
        return userRepository.existsByEmailIgnoreCase(
            normalizeEmail(email)
        )
    }

    @Transactional
    fun register(form: RegistrationForm): User {
        val normalizedEmail = normalizeEmail(email = form.email)

        require(
            !userRepository.existsByEmailIgnoreCase(normalizedEmail)
        ) {
            "Пользователь с таким email уже существует"
        }

        val user = User(
            email = normalizedEmail,
            passwordHash = passwordEncoder.encode(form.password),
            role = UserRole.USER,
            enabled = true
        )

        return userRepository.save(user)
    }

    private fun normalizeEmail(email: String): String {
        return email.trim().lowercase()
    }
}