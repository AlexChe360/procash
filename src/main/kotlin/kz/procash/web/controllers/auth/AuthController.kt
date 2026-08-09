package kz.procash.web.controllers.auth

import jakarta.validation.Valid
import kz.procash.service.auth.RegistrationService
import org.springframework.stereotype.Controller
import org.springframework.ui.Model
import org.springframework.validation.BindingResult
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.ModelAttribute
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.servlet.mvc.support.RedirectAttributes
import java.security.Principal

@Controller
class AuthController(
    private val registrationService: RegistrationService
) {
    @GetMapping("/login")
    fun login(
        principal: Principal?
    ): String {
        if (principal != null) {
            return "redirect:/dashboard"
        }

        return "auth/login"
    }

    @GetMapping("/register")
    fun registerPage(
        principal: Principal?,
        model: Model
    ): String {
        if (principal != null) {
            return "redirect:/dashboard"
        }

        if (!model.containsAttribute("registrationForm")) {
            model.addAttribute(
                "registrationForm",
                RegistrationForm()
            )
        }

        return "auth/register"
    }

    @PostMapping("/register")
    fun register(
        @Valid
        @ModelAttribute("registrationForm")
        form: RegistrationForm,
        bindingResult: BindingResult,
        redirectAttributes: RedirectAttributes
    ): String {
        if (form.password != form.passwordConfirmation) {
            bindingResult.rejectValue(
                "passwordConfirmation",
                "passwordConfirmation.mismatch",
                "Пароли не совпадают"
            )
        }

        if (registrationService.emailExists(form.email)) {
            bindingResult.rejectValue(
                "email",
                "email.alreadyExists",
                "Пользователь с таким email уже зарегистрирован"
            )
        }

        if (bindingResult.hasErrors()) {
            return "auth/register"
        }

        registrationService.register(form)

        redirectAttributes.addFlashAttribute(
            "registrationSuccess",
            true
        )

        return "redirect:/login?registered"
    }
}