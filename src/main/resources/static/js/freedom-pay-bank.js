document.addEventListener("DOMContentLoaded", () => {
    const ibanInput = document.querySelector("#iban");
    const bicInput = document.querySelector("#bankBic");

    if (ibanInput) {
        ibanInput.addEventListener("input", () => {
            const cursorPosition = ibanInput.selectionStart ?? 0;

            const normalized = ibanInput.value
                .replace(/[^a-zA-Z0-9]/g, "")
                .toUpperCase()
                .slice(0, 20);

            ibanInput.value = normalized
                .replace(/(.{4})/g, "$1 ")
                .trim();

            ibanInput.setSelectionRange(
                ibanInput.value.length,
                ibanInput.value.length
            );
        });
    }

    if (bicInput) {
        bicInput.addEventListener("input", () => {
            bicInput.value = bicInput.value
                .replace(/[^a-zA-Z0-9]/g, "")
                .toUpperCase()
                .slice(0, 11);
        });
    }
});