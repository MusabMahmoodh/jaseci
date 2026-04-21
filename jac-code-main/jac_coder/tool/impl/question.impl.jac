impl ask_question(question: str, options: str = "") -> str {
    if not question {
        return "Error: question is required";
    }

    if os.environ.get("JACCODER_WEB_MODE", "") {
        return "Cannot ask user interactively in web mode. Proceed with your best judgment.";
    }

    print(f"\n{YELLOW}[Question]{RESET} {question}");

    if options {
        choices = [o.strip() for o in options.split(",")];
        for (i, opt) in enumerate(choices) {
            print(f"  {i + 1}. {opt}");
        }
        answer = input("Your choice (number or text): ").strip();
        try {
            idx = int(answer) - 1;
            if 0 <= idx < len(choices) {
                answer = choices[idx];
            }
        } except ValueError { }
    } else {
        answer = input("Your answer: ").strip();
    }

    return f"User answered: {answer}";
}
