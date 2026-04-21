import from react { useEffect }
import from "..ui.scroll-area" { ScrollArea }
import from ..ui.switch { Switch }
import from ..ui.separator { Separator }
import from ..ui.field { Field, FieldLabel }
import from ..ui.select { Select, SelectTrigger, SelectValue, SelectContent, SelectItem }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { MapsIcon, TextWrapIcon, Key01Icon, Sun03Icon, AiChat02Icon }
import from .EnvVarPanel { EnvVarPanel }

def:pub SettingsPanel(props: Any) -> Any {
    settings = props.settings;
    showMinimap = props.showMinimap or False;
    onToggleMinimap = props.onToggleMinimap;
    wordWrap = props.wordWrap or False;
    onToggleWordWrap = props.onToggleWordWrap;
    theme = props.theme or "dark";
    onThemeChange = props.onThemeChange;

    return <div className="flex flex-col h-full overflow-hidden bg-card">
        <div className="p-3 text-[11px] font-semibold uppercase tracking-[0.05em] text-muted-foreground border-b border-border">
            {"Settings"}
        </div>

        <ScrollArea className="flex-1">
            <div className="flex flex-col">
                <div className="p-3">
                    <span className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground block mb-2.5">
                        {"Appearance"}
                    </span>
                    <div className="flex flex-col gap-3">
                        <Field orientation="horizontal">
                            <FieldLabel className="flex items-center gap-1.5 text-xs text-muted-foreground">
                                <HugeiconsIcon icon={Sun03Icon} strokeWidth={2} className="size-3.5" />
                                {"Theme"}
                            </FieldLabel>
                            <Select
                                value={theme}
                                onValueChange={lambda v: Any { if onThemeChange { onThemeChange(v); } }}
                            >
                                <SelectTrigger className="h-7 w-[110px] text-xs">
                                    <SelectValue />
                                </SelectTrigger>
                                <SelectContent>
                                    <SelectItem value="light">{"Light"}</SelectItem>
                                    <SelectItem value="dark">{"Dark"}</SelectItem>
                                    <SelectItem value="system">{"System"}</SelectItem>
                                </SelectContent>
                            </Select>
                        </Field>
                    </div>
                </div>

                <Separator className="bg-border" />

                <div className="p-3">
                    <span className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground block mb-2.5">
                        {"Editor"}
                    </span>
                    <div className="flex flex-col gap-3">
                        <Field orientation="horizontal">
                            <FieldLabel className="flex items-center gap-1.5 text-xs text-muted-foreground">
                                <HugeiconsIcon icon={MapsIcon} strokeWidth={2} className="size-3.5" />
                                {"Minimap"}
                            </FieldLabel>
                            <Switch
                                size="sm"
                                checked={showMinimap}
                                onCheckedChange={lambda(_: Any) -> None { onToggleMinimap(); }}
                            />
                        </Field>
                        <Field orientation="horizontal">
                            <FieldLabel className="flex items-center gap-1.5 text-xs text-muted-foreground">
                                <HugeiconsIcon icon={TextWrapIcon} strokeWidth={2} className="size-3.5" />
                                {"Word Wrap"}
                            </FieldLabel>
                            <Switch
                                size="sm"
                                checked={wordWrap}
                                onCheckedChange={lambda(_: Any) -> None { onToggleWordWrap(); }}
                            />
                        </Field>
                    </div>
                </div>

                <Separator className="bg-border" />

                <div className="p-3">
                    <span className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground block mb-2.5">
                        {"AI Model"}
                    </span>
                    <div className="flex flex-col gap-2">
                        <Field orientation="horizontal">
                            <FieldLabel className="flex items-center gap-1.5 text-xs text-muted-foreground">
                                <HugeiconsIcon icon={AiChat02Icon} strokeWidth={2} className="size-3.5" />
                                {"Model"}
                            </FieldLabel>
                            <Select
                                value={settings and settings.aiModel or "default"}
                                onValueChange={lambda v: Any { if settings and settings.onAiModelChange { settings.onAiModelChange(v); } }}
                            >
                                <SelectTrigger className="h-7 w-[200px] text-xs">
                                    <SelectValue />
                                </SelectTrigger>
                                <SelectContent>
                                    <SelectItem value="default">{"Default (server)"}</SelectItem>
                                    <SelectItem value="claude-opus-4-6">{"Claude Opus 4.6"}</SelectItem>
                                    <SelectItem value="claude-sonnet-4-6">{"Claude Sonnet 4.6"}</SelectItem>
                                    <SelectItem value="claude-sonnet-4-5-20250929">{"Claude Sonnet 4.5"}</SelectItem>
                                    <SelectItem value="claude-opus-4-5-20251101">{"Claude Opus 4.5"}</SelectItem>
                                    <SelectItem value="gpt-5.4">{"GPT 5.4"}</SelectItem>
                                    <SelectItem value="gpt-5.2">{"GPT 5.2"}</SelectItem>
                                </SelectContent>
                            </Select>
                        </Field>
                        <p className="text-[10px] text-muted-foreground">
                            {"Select an AI model for the chat agent. Requires a matching API key in Environment Variables below."}
                        </p>
                    </div>
                </div>

                <Separator className="bg-border" />

                <div className="p-3">
                    <div className="flex items-center gap-1.5 mb-2.5">
                        <HugeiconsIcon icon={Key01Icon} strokeWidth={2} className="size-3.5 text-muted-foreground" />
                        <span className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">
                            {"Environment Variables"}
                        </span>
                    </div>
                    {settings and <EnvVarPanel settings={settings} /> or <span className="text-xs text-muted-foreground">{"Open a project to manage environment variables."}</span>}
                </div>
            </div>
        </ScrollArea>
    </div>;
}
