# Step 10: Final Integration - Complete Todo App

Congratulations on making it this far! In this final step, we'll bring everything together into a complete, production-ready todo application.

## What You've Built

You've learned:
- ✅ Creating Jac applications
- ✅ Building reusable components
- ✅ Styling with inline CSS
- ✅ Managing state with `useState`
- ✅ Side effects with `useEffect`
- ✅ Client-side routing
- ✅ Backend logic with walkers
- ✅ User authentication
- ✅ Data persistence

Now let's combine it all!

## Complete Application Code

Here's the entire app in one file:

```jac
# ============================================
# BACKEND: Data Models and Walkers
# ============================================

node Todo {
    has text: str;
    has done: bool = False;
}

walker create_todo {
    has text: str;

    class __specs__ {
        has auth: bool = True;
    }

    can create with `root entry {
        new_todo = here ++> Todo(text=self.text);
        report new_todo;
    }
}

walker read_todos {
    class __specs__ {
        has auth: bool = True;
    }

    can read with `root entry {
        visit [-->(`?Todo)];
    }

    can report_todos with exit {
        report here;
    }
}

walker toggle_todo {
    class __specs__ {
        has auth: bool = True;
    }

    can toggle with Todo entry {
        here.done = not here.done;
        report here;
    }
}

walker delete_todo {
    class __specs__ {
        has auth: bool = True;
    }

    can delete with Todo entry {
        del here;
    }
}

# ============================================
# FRONTEND: React Application
# ============================================

cl import from react {useState, useEffect}
cl import from "@jac-client/utils" {
    Router,
    Routes,
    Route,
    Link,
    useNavigate,
    jacIsLoggedIn,
    jacLogin,
    jacSignup,
    jacLogout,
    __jacSpawn
}

cl {
    # ============================================
    # CUSTOM HOOKS
    # ============================================

    def useAuth() -> dict {
        async def login(username: str, password: str) -> dict {
            try {
                result = await jacLogin(username, password);
                if result {
                    return {"success": True, "data": result, "error": None};
                }
                return {"success": False, "error": "Invalid credentials"};
            } except Exception {
                return {"success": False, "error": "Invalid credentials"};
            }
        }

        async def signup(username: str, password: str, confirmPassword: str) -> dict {
            if password != confirmPassword {
                return {"success": False, "error": "Passwords do not match"};
            }
            try {
                result = await jacSignup(username, password);
                if result {
                    return {"success": True, "data": result, "error": None};
                }
                return {"success": False, "error": "Unable to create account"};
            } except Exception as err {
                return {"success": False, "error": err.toString()};
            }
        }

        def logout() -> None {
            jacLogout();
        }

        def isAuthenticated() -> bool {
            return jacIsLoggedIn();
        }

        return {
            "login": login,
            "signup": signup,
            "logout": logout,
            "isAuthenticated": isAuthenticated
        };
    }

    def useTodos() -> dict {
        let [state, setState] = useState({
            "todos": [],
            "inputValue": "",
            "filter": "all",
            "loading": False,
            "error": ""
        });

        def flattenReports(raw: any) -> list {
            if not raw {
                return [];
            }
            if Array.isArray(raw) {
                let accumulator = [];
                raw.forEach(lambda entry: any -> None {
                    if Array.isArray(entry) {
                        entry.forEach(lambda nested: any -> None {
                            if nested {
                                accumulator.push(nested);
                            }
                        });
                    } elif entry {
                        accumulator.push(entry);
                    }
                });
                return accumulator;
            }
            return [raw];
        }

        async def loadTodos() -> None {
            let current = state;
            setState({
                "todos": current["todos"],
                "inputValue": current["inputValue"],
                "filter": current["filter"],
                "loading": True,
                "error": ""
            });

            try {
                let response = await __jacSpawn("read_todos", "", {});
                let items = flattenReports(response.reports);
                setState({
                    "todos": items,
                    "inputValue": current["inputValue"],
                    "filter": current["filter"],
                    "loading": False,
                    "error": ""
                });
            } except Exception as err {
                setState({
                    "todos": current["todos"],
                    "inputValue": current["inputValue"],
                    "filter": current["filter"],
                    "loading": False,
                    "error": err.toString()
                });
            }
        }

        async def addTodo() -> None {
            let current = state;
            let text = current["inputValue"].trim();
            if not text {
                return;
            }

            try {
                let result = await __jacSpawn("create_todo", "", {"text": text});
                let reportItems = flattenReports(result.reports);
                let created = None;
                if reportItems.length > 0 {
                    created = reportItems[0];
                }

                if created {
                    let updatedTodos = current["todos"].concat([created]);
                    setState({
                        "todos": updatedTodos,
                        "inputValue": "",
                        "filter": current["filter"],
                        "loading": False,
                        "error": ""
                    });
                } else {
                    await loadTodos();
                }
            } except Exception as err {
                setState({
                    "todos": current["todos"],
                    "inputValue": current["inputValue"],
                    "filter": current["filter"],
                    "loading": False,
                    "error": err.toString()
                });
            }
        }

        async def toggleTodo(id: any) -> None {
            let current = state;
            try {
                await __jacSpawn("toggle_todo", id, {});
                let transformed = current["todos"].map(lambda todo: any -> any {
                    if todo._jac_id == id {
                        return {
                            "_jac_id": todo._jac_id,
                            "text": todo.text,
                            "done": not todo.done
                        };
                    }
                    return todo;
                });
                setState({
                    "todos": transformed,
                    "inputValue": current["inputValue"],
                    "filter": current["filter"],
                    "loading": False,
                    "error": ""
                });
            } except Exception as err {
                setState({
                    "todos": current["todos"],
                    "inputValue": current["inputValue"],
                    "filter": current["filter"],
                    "loading": False,
                    "error": err.toString()
                });
            }
        }

        async def deleteTodo(id: any) -> None {
            let current = state;
            try {
                await __jacSpawn("delete_todo", id, {});
                let remaining = current["todos"].filter(lambda todo: any -> bool {
                    return todo._jac_id != id;
                });
                setState({
                    "todos": remaining,
                    "inputValue": current["inputValue"],
                    "filter": current["filter"],
                    "loading": False,
                    "error": ""
                });
            } except Exception as err {
                console.error("Error deleting todo:", err);
            }
        }

        def setInputValue(value: str) -> None {
            let current = state;
            setState({
                "todos": current["todos"],
                "inputValue": value,
                "filter": current["filter"],
                "loading": current["loading"],
                "error": current["error"]
            });
        }

        def setFilter(value: str) -> None {
            let current = state;
            setState({
                "todos": current["todos"],
                "inputValue": current["inputValue"],
                "filter": value,
                "loading": current["loading"],
                "error": current["error"]
            });
        }

        def getFilteredTodos() -> list {
            let current = state;
            if current["filter"] == "active" {
                return current["todos"].filter(lambda todo: any -> bool {
                    return not todo.done;
                });
            } elif current["filter"] == "completed" {
                return current["todos"].filter(lambda todo: any -> bool {
                    return todo.done;
                });
            }
            return current["todos"];
        }

        def getActiveCount() -> int {
            let current = state;
            return current["todos"].filter(lambda todo: any -> bool {
                return not todo.done;
            }).length;
        }

        def hasCompleted() -> bool {
            let current = state;
            return current["todos"].some(lambda todo: any -> bool {
                return todo.done;
            });
        }

        def clearCompleted() -> None {
            let current = state;
            let active = current["todos"].filter(lambda todo: any -> bool {
                return not todo.done;
            });
            setState({
                "todos": active,
                "inputValue": current["inputValue"],
                "filter": current["filter"],
                "loading": current["loading"],
                "error": current["error"]
            });
        }

        def getState() -> dict {
            return state;
        }

        return {
            "state": getState,
            "loadTodos": loadTodos,
            "addTodo": addTodo,
            "toggleTodo": toggleTodo,
            "deleteTodo": deleteTodo,
            "clearCompleted": clearCompleted,
            "setInputValue": setInputValue,
            "setFilter": setFilter,
            "getFilteredTodos": getFilteredTodos,
            "getActiveCount": getActiveCount,
            "hasCompleted": hasCompleted
        };
    }

    # ============================================
    # PAGE COMPONENTS
    # ============================================

    def LoginPage() -> any {
        let [state, setState] = useState({
            "username": "",
            "password": "",
            "loading": False,
            "error": ""
        });

        let navigate = useNavigate();
        let auth = useAuth();

        useEffect(lambda -> None {
            if jacIsLoggedIn() {
                navigate("/dashboard");
            }
        }, []);

        async def handleSubmit(event: any) -> None {
            event.preventDefault();
            let current = state;
            setState({
                "username": current["username"],
                "password": current["password"],
                "loading": True,
                "error": ""
            });

            try {
                let result = await auth["login"](current["username"], current["password"]);
                if result["success"] {
                    navigate("/dashboard");
                } else {
                    setState({
                        "username": current["username"],
                        "password": current["password"],
                        "loading": False,
                        "error": result["error"]
                    });
                }
            } except Exception as err {
                setState({
                    "username": current["username"],
                    "password": current["password"],
                    "loading": False,
                    "error": err.toString()
                });
            }
        }

        return <div style={{
            "display": "flex",
            "justifyContent": "center",
            "alignItems": "center",
            "minHeight": "calc(100vh - 64px)",
            "padding": "20px"
        }}>
            <div style={{
                "width": "100%",
                "maxWidth": "420px",
                "backgroundColor": "#ffffff",
                "padding": "32px",
                "borderRadius": "16px",
                "boxShadow": "0 10px 30px rgba(15, 23, 42, 0.08)"
            }}>
                <h1 style={{
                    "margin": "0 0 8px",
                    "fontSize": "28px",
                    "fontWeight": "700",
                    "color": "#1e293b"
                }}>
                    Welcome back
                </h1>
                <p style={{
                    "margin": "0 0 24px",
                    "color": "#64748b",
                    "fontSize": "15px"
                }}>
                    Sign in to access your todos
                </p>

                {(state["error"] != "") ? (
                    <div style={{
                        "marginBottom": "16px",
                        "padding": "12px",
                        "borderRadius": "8px",
                        "backgroundColor": "#fee2e2",
                        "color": "#b91c1c",
                        "fontSize": "14px"
                    }}>
                        {state["error"]}
                    </div>
                ) : <span></span>}

                <form onSubmit={handleSubmit} style={{
                    "display": "flex",
                    "flexDirection": "column",
                    "gap": "16px"
                }}>
                    <label style={{
                        "display": "flex",
                        "flexDirection": "column",
                        "gap": "8px"
                    }}>
                        <span style={{
                            "fontSize": "14px",
                            "fontWeight": "500",
                            "color": "#475569"
                        }}>
                            Username
                        </span>
                        <input
                            type="text"
                            value={state["username"]}
                            onChange={lambda e: any -> None {
                                setState({
                                    "username": e.target.value,
                                    "password": state["password"],
                                    "loading": state["loading"],
                                    "error": ""
                                });
                            }}
                            placeholder="Enter your username"
                            style={{
                                "padding": "12px 14px",
                                "borderRadius": "10px",
                                "border": "1px solid #d1d5db",
                                "fontSize": "15px",
                                "outline": "none"
                            }}
                            required={True}
                        />
                    </label>

                    <label style={{
                        "display": "flex",
                        "flexDirection": "column",
                        "gap": "8px"
                    }}>
                        <span style={{
                            "fontSize": "14px",
                            "fontWeight": "500",
                            "color": "#475569"
                        }}>
                            Password
                        </span>
                        <input
                            type="password"
                            value={state["password"]}
                            onChange={lambda e: any -> None {
                                setState({
                                    "username": state["username"],
                                    "password": e.target.value,
                                    "loading": state["loading"],
                                    "error": ""
                                });
                            }}
                            placeholder="Enter your password"
                            style={{
                                "padding": "12px 14px",
                                "borderRadius": "10px",
                                "border": "1px solid #d1d5db",
                                "fontSize": "15px",
                                "outline": "none"
                            }}
                            required={True}
                        />
                    </label>

                    <button
                        type="submit"
                        disabled={state["loading"]}
                        style={{
                            "padding": "12px",
                            "borderRadius": "10px",
                            "backgroundColor": "#6366f1",
                            "color": "#ffffff",
                            "fontWeight": "600",
                            "fontSize": "15px",
                            "border": "none",
                            "cursor": (("not-allowed" if state["loading"] else "pointer")),
                            "opacity": ((0.6 if state["loading"] else 1))
                        }}
                    >
                        {(("Signing in..." if state["loading"] else "Sign in"))}
                    </button>
                </form>

                <p style={{
                    "marginTop": "24px",
                    "fontSize": "14px",
                    "color": "#64748b",
                    "textAlign": "center"
                }}>
                    Don't have an account?{" "}
                    <Link to="/signup" style={{
                        "color": "#3b82f6",
                        "textDecoration": "none",
                        "fontWeight": "600"
                    }}>
                        Create one
                    </Link>
                </p>
            </div>
        </div>;
    }

    def SignupPage() -> any {
        let [state, setState] = useState({
            "username": "",
            "password": "",
            "confirmPassword": "",
            "loading": False,
            "error": ""
        });

        let navigate = useNavigate();
        let auth = useAuth();

        useEffect(lambda -> None {
            if jacIsLoggedIn() {
                navigate("/dashboard");
            }
        }, []);

        async def handleSubmit(event: any) -> None {
            event.preventDefault();
            let current = state;
            setState({
                "username": current["username"],
                "password": current["password"],
                "confirmPassword": current["confirmPassword"],
                "loading": True,
                "error": ""
            });

            try {
                let result = await auth["signup"](
                    current["username"],
                    current["password"],
                    current["confirmPassword"]
                );

                if result["success"] {
                    navigate("/dashboard");
                } else {
                    setState({
                        "username": current["username"],
                        "password": current["password"],
                        "confirmPassword": current["confirmPassword"],
                        "loading": False,
                        "error": result["error"]
                    });
                }
            } except Exception as err {
                setState({
                    "username": current["username"],
                    "password": current["password"],
                    "confirmPassword": current["confirmPassword"],
                    "loading": False,
                    "error": err.toString()
                });
            }
        }

        return <div style={{
            "display": "flex",
            "justifyContent": "center",
            "alignItems": "center",
            "minHeight": "calc(100vh - 64px)",
            "padding": "20px"
        }}>
            <div style={{
                "width": "100%",
                "maxWidth": "420px",
                "backgroundColor": "#ffffff",
                "padding": "32px",
                "borderRadius": "16px",
                "boxShadow": "0 10px 30px rgba(15, 23, 42, 0.08)"
            }}>
                <h2 style={{
                    "margin": "0 0 12px",
                    "fontSize": "26px",
                    "color": "#1e293b"
                }}>
                    Create Account
                </h2>
                <p style={{
                    "margin": "0 0 20px",
                    "color": "#64748b"
                }}>
                    Join us to start managing your todos
                </p>

                {(state["error"] != "") ? (
                    <div style={{
                        "marginBottom": "16px",
                        "padding": "12px",
                        "borderRadius": "8px",
                        "backgroundColor": "#fee2e2",
                        "color": "#b91c1c"
                    }}>
                        {state["error"]}
                    </div>
                ) : <span></span>}

                <form onSubmit={handleSubmit} style={{
                    "display": "grid",
                    "gap": "16px"
                }}>
                    <label style={{
                        "display": "grid",
                        "gap": "6px"
                    }}>
                        <span style={{
                            "fontSize": "14px",
                            "fontWeight": "600",
                            "color": "#1e293b"
                        }}>
                            Username
                        </span>
                        <input
                            type="text"
                            value={state["username"]}
                            onChange={lambda e: any -> None {
                                setState({
                                    "username": e.target.value,
                                    "password": state["password"],
                                    "confirmPassword": state["confirmPassword"],
                                    "loading": state["loading"],
                                    "error": ""
                                });
                            }}
                            placeholder="Choose a username"
                            style={{
                                "padding": "12px 16px",
                                "borderRadius": "10px",
                                "border": "1px solid #e2e8f0",
                                "fontSize": "16px"
                            }}
                            required={True}
                        />
                    </label>

                    <label style={{
                        "display": "grid",
                        "gap": "6px"
                    }}>
                        <span style={{
                            "fontSize": "14px",
                            "fontWeight": "600",
                            "color": "#1e293b"
                        }}>
                            Password
                        </span>
                        <input
                            type="password"
                            value={state["password"]}
                            onChange={lambda e: any -> None {
                                setState({
                                    "username": state["username"],
                                    "password": e.target.value,
                                    "confirmPassword": state["confirmPassword"],
                                    "loading": state["loading"],
                                    "error": ""
                                });
                            }}
                            placeholder="Create a password"
                            style={{
                                "padding": "12px 16px",
                                "borderRadius": "10px",
                                "border": "1px solid #e2e8f0",
                                "fontSize": "16px"
                            }}
                            required={True}
                        />
                    </label>

                    <label style={{
                        "display": "grid",
                        "gap": "6px"
                    }}>
                        <span style={{
                            "fontSize": "14px",
                            "fontWeight": "600",
                            "color": "#1e293b"
                        }}>
                            Confirm Password
                        </span>
                        <input
                            type="password"
                            value={state["confirmPassword"]}
                            onChange={lambda e: any -> None {
                                setState({
                                    "username": state["username"],
                                    "password": state["password"],
                                    "confirmPassword": e.target.value,
                                    "loading": state["loading"],
                                    "error": ""
                                });
                            }}
                            placeholder="Confirm your password"
                            style={{
                                "padding": "12px 16px",
                                "borderRadius": "10px",
                                "border": "1px solid #e2e8f0",
                                "fontSize": "16px"
                            }}
                            required={True}
                        />
                    </label>

                    <button
                        type="submit"
                        disabled={state["loading"]}
                        style={{
                            "padding": "12px",
                            "borderRadius": "10px",
                            "backgroundColor": "#22c55e",
                            "color": "#ffffff",
                            "fontWeight": "600",
                            "fontSize": "16px",
                            "border": "none",
                            "cursor": (("not-allowed" if state["loading"] else "pointer")),
                            "opacity": ((0.6 if state["loading"] else 1))
                        }}
                    >
                        {(("Creating..." if state["loading"] else "Create Account"))}
                    </button>
                </form>

                <p style={{
                    "marginTop": "16px",
                    "textAlign": "center",
                    "color": "#64748b"
                }}>
                    Already have an account?{" "}
                    <Link to="/login" style={{
                        "color": "#6366f1",
                        "textDecoration": "none",
                        "fontWeight": "600"
                    }}>
                        Sign in
                    </Link>
                </p>
            </div>
        </div>;
    }

    def DashboardPage() -> any {
        let todosHook = useTodos();

        useEffect(lambda -> None {
            todosHook["loadTodos"]();
        }, []);

        let state = todosHook["state"]();
        let filteredTodos = todosHook["getFilteredTodos"]();
        let activeCount = todosHook["getActiveCount"]();

        return <div style={{
            "maxWidth": "720px",
            "margin": "0 auto",
            "padding": "24px"
        }}>
            <h1 style={{
                "textAlign": "center",
                "color": "#1f2937",
                "marginBottom": "24px",
                "fontSize": "2.5rem",
                "fontWeight": "700"
            }}>
                📝 My Todos
            </h1>

            {(state["loading"]) ? (
                <div style={{
                    "marginBottom": "16px",
                    "padding": "12px",
                    "borderRadius": "8px",
                    "backgroundColor": "#e0f2fe",
                    "color": "#075985"
                }}>
                    Loading todos...
                </div>
            ) : <span></span>}

            {(state["error"] != "") ? (
                <div style={{
                    "marginBottom": "16px",
                    "padding": "12px",
                    "borderRadius": "8px",
                    "backgroundColor": "#fee2e2",
                    "color": "#b91c1c"
                }}>
                    {state["error"]}
                </div>
            ) : <span></span>}

            <div style={{
                "display": "flex",
                "gap": "8px",
                "marginBottom": "24px",
                "backgroundColor": "#ffffff",
                "padding": "16px",
                "borderRadius": "12px",
                "boxShadow": "0 1px 3px rgba(0,0,0,0.1)"
            }}>
                <input
                    type="text"
                    value={state["inputValue"]}
                    onChange={lambda e: any -> None {
                        todosHook["setInputValue"](e.target.value);
                    }}
                    onKeyPress={lambda e: any -> None {
                        if e.key == "Enter" {
                            todosHook["addTodo"]();
                        }
                    }}
                    placeholder="What needs to be done?"
                    style={{
                        "flex": "1",
                        "padding": "12px 16px",
                        "border": "1px solid #e5e7eb",
                        "borderRadius": "8px",
                        "fontSize": "16px",
                        "outline": "none"
                    }}
                />
                <button
                    onClick={lambda -> None {
                        todosHook["addTodo"]();
                    }}
                    style={{
                        "padding": "12px 24px",
                        "backgroundColor": "#3b82f6",
                        "color": "#ffffff",
                        "border": "none",
                        "borderRadius": "8px",
                        "fontSize": "16px",
                        "fontWeight": "600",
                        "cursor": "pointer"
                    }}
                >
                    Add
                </button>
            </div>

            <div style={{
                "display": "flex",
                "gap": "8px",
                "marginBottom": "24px",
                "justifyContent": "center"
            }}>
                <button
                    onClick={lambda -> None {
                        todosHook["setFilter"]("all");
                    }}
                    style={{
                        "padding": "8px 16px",
                        "backgroundColor": (("#3b82f6" if state["filter"] == "all" else "#ffffff")),
                        "color": (("#ffffff" if state["filter"] == "all" else "#3b82f6")),
                        "border": "1px solid #3b82f6",
                        "borderRadius": "6px",
                        "fontSize": "14px",
                        "fontWeight": "600",
                        "cursor": "pointer"
                    }}
                >
                    All
                </button>
                <button
                    onClick={lambda -> None {
                        todosHook["setFilter"]("active");
                    }}
                    style={{
                        "padding": "8px 16px",
                        "backgroundColor": (("#3b82f6" if state["filter"] == "active" else "#ffffff")),
                        "color": (("#ffffff" if state["filter"] == "active" else "#3b82f6")),
                        "border": "1px solid #3b82f6",
                        "borderRadius": "6px",
                        "fontSize": "14px",
                        "fontWeight": "600",
                        "cursor": "pointer"
                    }}
                >
                    Active
                </button>
                <button
                    onClick={lambda -> None {
                        todosHook["setFilter"]("completed");
                    }}
                    style={{
                        "padding": "8px 16px",
                        "backgroundColor": (("#3b82f6" if state["filter"] == "completed" else "#ffffff")),
                        "color": (("#ffffff" if state["filter"] == "completed" else "#3b82f6")),
                        "border": "1px solid #3b82f6",
                        "borderRadius": "6px",
                        "fontSize": "14px",
                        "fontWeight": "600",
                        "cursor": "pointer"
                    }}
                >
                    Completed
                </button>
            </div>

            <div style={{
                "backgroundColor": "#ffffff",
                "borderRadius": "12px",
                "boxShadow": "0 1px 3px rgba(0,0,0,0.1)",
                "overflow": "hidden"
            }}>
                {(filteredTodos.length == 0) ? (
                    <div style={{
                        "padding": "40px",
                        "textAlign": "center",
                        "color": "#9ca3af"
                    }}>
                        {(
                            "No todos yet. Add one above!"
                            if state["filter"] == "all" else (
                                "No active todos!"
                                if state["filter"] == "active" else
                                "No completed todos!"
                            )
                        )}
                    </div>
                ) : (
                    filteredTodos.map(lambda todo: any -> any {
                        return <div key={todo._jac_id} style={{
                            "display": "flex",
                            "alignItems": "center",
                            "gap": "12px",
                            "padding": "16px",
                            "borderBottom": "1px solid #e5e7eb"
                        }}>
                            <input
                                type="checkbox"
                                checked={todo.done}
                                onChange={lambda -> None {
                                    todosHook["toggleTodo"](todo._jac_id);
                                }}
                                style={{
                                    "width": "20px",
                                    "height": "20px",
                                    "cursor": "pointer"
                                }}
                            />
                            <span style={{
                                "flex": "1",
                                "textDecoration": (("line-through" if todo.done else "none")),
                                "color": (("#9ca3af" if todo.done else "#1f2937")),
                                "fontSize": "16px"
                            }}>
                                {todo.text}
                            </span>
                            <button
                                onClick={lambda -> None {
                                    todosHook["deleteTodo"](todo._jac_id);
                                }}
                                style={{
                                    "padding": "6px 12px",
                                    "backgroundColor": "#ef4444",
                                    "color": "#ffffff",
                                    "border": "none",
                                    "borderRadius": "6px",
                                    "fontSize": "14px",
                                    "fontWeight": "500",
                                    "cursor": "pointer"
                                }}
                            >
                                Delete
                            </button>
                        </div>;
                    })
                )}
            </div>

            {(state["todos"].length > 0) ? (
                <div style={{
                    "display": "flex",
                    "justifyContent": "space-between",
                    "alignItems": "center",
                    "marginTop": "24px",
                    "padding": "16px",
                    "backgroundColor": "#ffffff",
                    "borderRadius": "12px",
                    "boxShadow": "0 1px 3px rgba(0,0,0,0.1)"
                }}>
                    <span style={{
                        "color": "#6b7280",
                        "fontSize": "14px"
                    }}>
                        {activeCount} {(("item" if activeCount == 1 else "items"))} left
                    </span>
                    {(todosHook["hasCompleted"]()) ? (
                        <button
                            onClick={lambda -> None {
                                todosHook["clearCompleted"]();
                            }}
                            style={{
                                "padding": "8px 16px",
                                "backgroundColor": "#ef4444",
                                "color": "#ffffff",
                                "border": "none",
                                "borderRadius": "6px",
                                "fontSize": "14px",
                                "fontWeight": "600",
                                "cursor": "pointer"
                            }}
                        >
                            Clear Completed
                        </button>
                    ) : <span></span>}
                </div>
            ) : <span></span>}
        </div>;
    }

    def AppHeader() -> any {
        let navigate = useNavigate();
        let auth = useAuth();
        let isAuthed = jacIsLoggedIn();

        def handleLogout(event: any) -> None {
            event.preventDefault();
            auth["logout"]();
            navigate("/login");
        }

        let authCta = <Link to="/login" style={{
            "padding": "8px 14px",
            "borderRadius": "8px",
            "border": "1px solid #6366f1",
            "color": "#6366f1",
            "textDecoration": "none",
            "fontWeight": "600"
        }}>
            Sign in
        </Link>;

        if isAuthed {
            authCta = <button
                onClick={handleLogout}
                style={{
                    "padding": "8px 14px",
                    "borderRadius": "8px",
                    "border": "1px solid #ef4444",
                    "backgroundColor": "#fef2f2",
                    "color": "#b91c1c",
                    "cursor": "pointer",
                    "fontWeight": "600"
                }}
            >
                Sign out
            </button>;
        }

        let dashboardLink = None;
        if isAuthed {
            dashboardLink = <Link to="/dashboard" style={{
                "color": "#0f172a",
                "textDecoration": "none",
                "fontWeight": "600"
            }}>
                Dashboard
            </Link>;
        }

        return <header style={{
            "backgroundColor": "#ffffff",
            "borderBottom": "1px solid #e2e8f0",
            "padding": "12px 24px"
        }}>
            <div style={{
                "maxWidth": "1080px",
                "margin": "0 auto",
                "display": "flex",
                "alignItems": "center",
                "gap": "16px",
                "justifyContent": "space-between",
                "flexWrap": "wrap"
            }}>
                <div style={{
                    "display": "flex",
                    "alignItems": "center",
                    "gap": "16px"
                }}>
                    <nav style={{
                        "display": "flex",
                        "gap": "12px",
                        "alignItems": "center"
                    }}>
                        <Link to="/login" style={{
                            "color": "#475569",
                            "textDecoration": "none"
                        }}>
                            Login
                        </Link>
                        <Link to="/signup" style={{
                            "color": "#475569",
                            "textDecoration": "none"
                        }}>
                            Sign up
                        </Link>
                        {dashboardLink}
                    </nav>
                </div>
                {authCta}
            </div>
        </header>;
    }

    # ============================================
    # MAIN APP
    # ============================================

    def app() -> any {
        return <Router defaultRoute="/login">
            <div style={{
                "minHeight": "100vh",
                "fontFamily": "sans-serif",
                "backgroundColor": "#f1f5f9"
            }}>
                <AppHeader />
                <main style={{
                    "maxWidth": "1080px",
                    "margin": "0 auto",
                    "width": "100%"
                }}>
                    <Routes>
                        <Route path="/login" component={LoginPage} />
                        <Route path="/signup" component={SignupPage} />
                        <Route
                            path="/dashboard"
                            component={DashboardPage}
                            guard={jacIsLoggedIn}
                        />
                    </Routes>
                </main>
            </div>
        </Router>;
    }
}
```

## Running the Complete App

1. **Save the code** to `app.jac`

2. **Start the server:**
   ```bash
   jac serve app.jac
   ```

3. **Open in browser:**
   - Go to `http://localhost:8000`

4. **Test it out:**
   - Create an account at `/signup`
   - Login at `/login`
   - Create, complete, and delete todos
   - Try filtering (All/Active/Completed)
   - Logout and login again - your todos persist!

## Features You've Built

✅ **Authentication:**
- User signup with password confirmation
- Secure login
- Session persistence
- Protected routes

✅ **Todo Management:**
- Create todos
- Mark as complete/incomplete
- Delete todos
- Filter by status (all/active/completed)
- Clear completed todos
- Item counter

✅ **UI/UX:**
- Responsive design
- Beautiful styling
- Loading states
- Error handling
- Empty states

✅ **Backend:**
- Data persistence
- User isolation
- Graph-based data structure
- Automatic API endpoints

## What's Next?

Now that you have a complete app, you can:

### 1. Add More Features
- Edit todo text
- Due dates and priorities
- Categories/tags
- Search functionality
- Sort options

### 2. Improve UI
- Dark mode
- Animations
- Mobile responsiveness
- Drag-and-drop reordering

### 3. Deploy Your App
- Use Jac Cloud for hosting
- Deploy to Vercel/Netlify
- Set up custom domain

### 4. Learn More
- Explore advanced walker patterns
- Learn about Jac's AI features
- Build more complex data graphs
- Integrate external APIs

## Deployment Guide

### Quick Deploy with Jac Cloud

```bash
# Install jac-cloud
pip install jac-cloud

# Deploy your app
jac cloud deploy app.jac

# Your app is now live!
```

### Environment Setup

For production, you might want to configure:

```bash
# Set environment variables
export JAC_DATABASE_URL="postgresql://..."
export JAC_SECRET_KEY="your-secret-key"

# Run in production mode
jac serve app.jac --prod
```

## Troubleshooting

### Issue: Todos not persisting
**Solution**: Make sure walkers have `auth: bool = True`

### Issue: Can't login after signup
**Solution**: Check console for errors. Verify signup returns success.

### Issue: UI looks broken
**Solution**: Clear browser cache, check for JavaScript errors.

### Issue: Performance is slow
**Solution**: Add indexes to frequently queried data, use pagination for large lists.

## Congratulations! 🎉

You've built a complete, production-ready todo application with:
- Modern frontend (React via Jac)
- Secure backend (Walkers)
- User authentication
- Data persistence
- Beautiful UI

You've learned the fundamentals of full-stack development with Jac!

## Learn More

### Explore React Concepts
Want to dive deeper into the React patterns Jac uses?
- [React Official Documentation](https://react.dev/learn)
- [React Hooks Reference](https://react.dev/reference/react)

### Jac Resources
- [Jac Official Documentation](https://www.jac-lang.org)
- [Jac Examples Repository](https://github.com/Jaseci-Labs/jaclang)
- [Jac Community Forum](https://community.jac-lang.org)

## Share Your Creation!

Built something cool? Share it with the community:
- Tag `#JacLang` on social media
- Contribute examples to Jac repository
- Write about your experience

## Thank You!

Thank you for completing this walkthrough. You now have the skills to build full-stack applications with Jac. Keep building, keep learning, and most importantly - have fun coding! 🚀

---

**Happy coding with Jac!**

