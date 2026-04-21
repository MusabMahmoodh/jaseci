def:pub SeeItInAction() -> JsxElement {

    vscode_lines = [
        {"text": "  JacCoder", "cls": "text-orange-400/80 font-semibold text-xs tracking-wide uppercase"},
        {"text": "", "cls": "h-2 block"},
        {"text": "  You", "cls": "text-white/25 text-xs"},
        {"text": "  Add dark mode toggle to the settings page", "cls": "text-white/80 text-sm"},
        {"text": "", "cls": "h-3 block"},
        {"text": "  JacCoder", "cls": "text-white/25 text-xs"},
        {"text": "  I'll check your current component structure first.", "cls": "text-white/50 text-sm"},
        {"text": "", "cls": "h-2 block"},
        {"text": "  ✓ Analyzed Settings.cl.jac", "cls": "text-emerald-400/70 text-sm"},
        {"text": "  ✓ Created ThemeToggle.cl.jac", "cls": "text-emerald-400/70 text-sm"},
        {"text": "  ✓ Updated Settings.cl.jac", "cls": "text-emerald-400/70 text-sm"},
        {"text": "  ✓ Updated global.css", "cls": "text-emerald-400/70 text-sm"},
        {"text": "  ✓ All files pass jac_check", "cls": "text-emerald-400/70 text-sm"},
        {"text": "", "cls": "h-2 block"},
        {"text": "  Done — toggle added with system preference detection.", "cls": "text-white/60 font-medium text-sm"}
    ];

    return (
        <section id="see-it-in-action" className="relative py-32 px-6 section-glow">
            <div className="max-w-5xl mx-auto">
                <div className="text-center mb-14">
                    <div className="section-label mx-auto mb-5 w-fit">Product</div>
                    <h2 className="text-4xl md:text-5xl font-bold tracking-[-0.02em] mb-5">
                        <span className="gradient-text-subtle">See it in action</span>
                    </h2>
                    <p className="text-white/40 text-base md:text-lg max-w-lg mx-auto leading-relaxed">
                        JacCoder works directly inside VS Code — inline chat, real-time diffs, and full tool activity.
                    </p>
                </div>

                <div className="code-block rounded-2xl overflow-hidden terminal-glow">
                    <div className="flex items-center gap-1.5 px-4 py-3 border-b border-white/[0.04]">
                        <div className="w-2.5 h-2.5 rounded-full bg-white/10"></div>
                        <div className="w-2.5 h-2.5 rounded-full bg-white/10"></div>
                        <div className="w-2.5 h-2.5 rounded-full bg-white/10"></div>
                        <span className="ml-3 text-white/20 text-[0.6875rem] font-mono">
                            VS Code — JacCoder Panel
                        </span>
                    </div>
                    <div className="p-5 md:p-7 space-y-0.5 min-h-[380px]">
                        {[
                            <div key={str(i)} className={line["cls"] + " font-mono"}>
                                {line["text"] if line["text"] else " "}
                            </div>
                            for (i, line) in enumerate(vscode_lines)
                        ]}
                    </div>
                </div>
            </div>
        </section>
    );
}
