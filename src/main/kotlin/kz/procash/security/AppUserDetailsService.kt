package kz.procash.security

import kz.procash.repository.user.UserRepository
import org.springframework.security.core.userdetails.User
import org.springframework.security.core.userdetails.UserDetails
import org.springframework.security.core.userdetails.UserDetailsService
import org.springframework.security.core.userdetails.UsernameNotFoundException
import org.springframework.stereotype.Service

@Service
class AppUserDetailsService(
    private val userRepository: UserRepository
) : UserDetailsService {

    override fun loadUserByUsername(username: String): UserDetails {
        val email = username.trim().lowercase()

        val user = userRepository
            .findByEmailIgnoreCase(email)
            .orElseThrow {
                UsernameNotFoundException(
                    "Пользователь с email $email не найден"
                )
            }

        return User
            .withUsername(user.email)
            .password(user.passwordHash)
            .roles(user.role.name)
            .disabled(!user.enabled)
            .build()
    }
}