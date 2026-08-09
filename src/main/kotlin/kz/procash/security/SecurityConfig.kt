package kz.procash.security

import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.crypto.factory.PasswordEncoderFactories
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.security.web.SecurityFilterChain

@Configuration
class SecurityConfig {

    @Bean
    fun securityFilterChain(
        http: HttpSecurity
    ): SecurityFilterChain {
        http
            .authorizeHttpRequests { authorization ->
                authorization
                    .requestMatchers(
                        "/",
                        "/register",
                        "/login",
                        "/order/**",
                        "/payments/**",
                        "/api/v1/health",
                        "/actuator/health",
                        "/css/**",
                        "/js/**",
                        "/images/**",
                        "/documents/**",
                        "/favicon.ico",
                        "/error",
                        "/r/*/q/**"
                    )
                    .permitAll()
                    .requestMatchers("/admin/**")
                    .hasRole("ADMIN")
                    .anyRequest()
                    .authenticated()
            }
            .formLogin { form ->
                form
                    .loginPage("/login")
                    .loginProcessingUrl("/login")
                    .usernameParameter("email")
                    .passwordParameter("password")
                    .successHandler { _, response, authentication ->
                        val isAdmin = authentication.authorities.any {
                            it.authority == "ROLE_ADMIN"
                        }

                        if (isAdmin) {
                            response.sendRedirect("/admin")
                        } else {
                            response.sendRedirect("/dashboard")
                        }
                    }
                    .failureUrl("/login?error")
                    .permitAll()
            }
            .logout { logout ->
                logout
                    .logoutUrl("/logout")
                    .logoutSuccessUrl("/login?logout")
                    .invalidateHttpSession(true)
                    .deleteCookies("JSESSIONID")
                    .permitAll()
            }

        return http.build()
    }

    @Bean
    fun passwordEncoder(): PasswordEncoder {
        return PasswordEncoderFactories
            .createDelegatingPasswordEncoder()
    }
}