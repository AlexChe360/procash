package kz.procash

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

@SpringBootApplication
class ProcashApplication

fun main(args: Array<String>) {
    runApplication<ProcashApplication>(*args)
}
