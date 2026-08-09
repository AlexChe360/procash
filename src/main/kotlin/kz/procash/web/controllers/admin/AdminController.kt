package kz.procash.web.controllers.admin

import org.springframework.stereotype.Controller
import org.springframework.ui.Model
import org.springframework.web.bind.annotation.GetMapping
import java.security.Principal

@Controller
class AdminController {

    @GetMapping("/admin")
    fun dashboard(
        principal: Principal,
        model: Model
    ) : String {
        model.addAttribute("email", principal.name)

        return "admin/dashboard"
    }
}