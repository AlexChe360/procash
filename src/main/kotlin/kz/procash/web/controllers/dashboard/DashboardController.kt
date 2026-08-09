package kz.procash.web.controllers.dashboard

import org.springframework.stereotype.Controller
import org.springframework.ui.Model
import org.springframework.web.bind.annotation.GetMapping
import java.security.Principal

@Controller
class DashboardController {

    @GetMapping("/dashboard")
    fun dashboard(
        principal: Principal,
        model: Model
    ): String {
        model.addAttribute("email", principal.name)

        return "dashboard"
    }
}