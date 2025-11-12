# Simple Authentication App with Routing
cl import from react {useState,useEffect}
cl import from "@jac-client/utils" {Router, Routes, Route, Link, jacSignup, jacLogin, jacLogout, jacIsLoggedIn}

cl {
    # Navigation Component
    def Navigation() -> any {
        let isLoggedIn = jacIsLoggedIn();
        
        return <nav style={{
            "padding": "16px 24px",
            "background": "#667eea",
            "display": "flex",
            "justifyContent": "space-between",
            "alignItems": "center"
        }}>
            <div style={{
                "fontSize": "1.25rem",
                "fontWeight": "600",
                "color": "#ffffff"
            }}>MyApp</div>
            
            <div style={{"display": "flex", "gap": "16px"}}>
                {(<>
                    <Link to="/dashboard" style={{
                        "color": "#ffffff",
                        "textDecoration": "none"
                    }}>Dashboard</Link>
                    <button
                        onClick={lambda -> None {
                            jacLogout();
                            window.location.hash = "#/login";
                            window.location.reload();
                        }}
                        style={{
                            "background": "none",
                            "color": "#ffffff",
                            "border": "1px solid #ffffff",
                            "padding": "4px 12px",
                            "borderRadius": "4px",
                            "cursor": "pointer"
                        }}
                    >Logout</button>
                </>) if isLoggedIn else (<>
                    <Link to="/login" style={{
                        "color": "#ffffff",
                        "textDecoration": "none"
                    }}>Login</Link>
                    <Link to="/signup" style={{
                        "color": "#ffffff",
                        "textDecoration": "none"
                    }}>Sign Up</Link>
                </>)}
            </div>
        </nav>;
    }

    # Login Page
    def LoginPage() -> any {
        let [username, setUsername] = useState("");
        let [password, setPassword] = useState("");
        let [error, setError] = useState("");

        async def handleLogin(e: any) -> None {
            e.preventDefault();
            setError("");
            if not username or not password {
                setError("Please fill in all fields");
                return;
            }
            success = await jacLogin(username, password);
            if success {
                window.location.hash = "#/dashboard";
            } else {
                setError("Invalid credentials");
            }
        }

        return <div style={{
            "minHeight": "calc(100vh - 56px)",
            "display": "flex",
            "alignItems": "center",
            "justifyContent": "center",
            "background": "#f5f5f5"
        }}>
            <div style={{
                "background": "#ffffff",
                "padding": "32px",
                "borderRadius": "8px",
                "width": "300px",
                "boxShadow": "0 2px 8px rgba(0,0,0,0.1)"
            }}>
                <h2 style={{"marginBottom": "24px", "textAlign": "center"}}>Login</h2>
                <form onSubmit={handleLogin}>
                    <input
                        type="text"
                        value={username}
                        onChange={lambda e: any -> None { setUsername(e.target.value); }}
                        placeholder="Username"
                        style={{
                            "width": "100%",
                            "padding": "10px",
                            "marginBottom": "12px",
                            "border": "1px solid #ddd",
                            "borderRadius": "4px",
                            "boxSizing": "border-box"
                        }}
                    />
                    <input
                        type="password"
                        value={password}
                        onChange={lambda e: any -> None { setPassword(e.target.value); }}
                        placeholder="Password"
                        style={{
                            "width": "100%",
                            "padding": "10px",
                            "marginBottom": "12px",
                            "border": "1px solid #ddd",
                            "borderRadius": "4px",
                            "boxSizing": "border-box"
                        }}
                    />
                    {(<div style={{
                            "color": "#dc2626",
                            "fontSize": "14px",
                            "marginBottom": "12px"
                        }}>{error}</div>) if error else None}
                    <button
                        type="submit"
                        style={{
                            "width": "100%",
                            "padding": "10px",
                            "background": "#667eea",
                            "color": "#ffffff",
                            "border": "none",
                            "borderRadius": "4px",
                            "cursor": "pointer",
                            "fontWeight": "600"
                        }}
                    >Login</button>
                </form>
                <p style={{"textAlign": "center", "marginTop": "16px", "fontSize": "14px"}}>
                    Need an account? <Link to="/signup">Sign up</Link>
                </p>
            </div>
        </div>;
    }

    # Signup Page
    def SignupPage() -> any {
        let [username, setUsername] = useState("");
        let [password, setPassword] = useState("");
        let [error, setError] = useState("");

        async def handleSignup(e: any) -> None {
            e.preventDefault();
            setError("");
            if not username or not password {
                setError("Please fill in all fields");
                return;
            }
            result = await jacSignup(username, password);
            if result["success"] {
                window.location.hash = "#/dashboard";
            } else {
                setError(result["error"] if result["error"] else "Signup failed");
            }
        }

        return <div style={{
            "minHeight": "calc(100vh - 56px)",
            "display": "flex",
            "alignItems": "center",
            "justifyContent": "center",
            "background": "#f5f5f5"
        }}>
            <div style={{
                "background": "#ffffff",
                "padding": "32px",
                "borderRadius": "8px",
                "width": "300px",
                "boxShadow": "0 2px 8px rgba(0,0,0,0.1)"
            }}>
                <h2 style={{"marginBottom": "24px", "textAlign": "center"}}>Sign Up</h2>
                <form onSubmit={handleSignup}>
                    <input
                        type="text"
                        value={username}
                        onChange={lambda e: any -> None { setUsername(e.target.value); }}
                        placeholder="Username"
                        style={{
                            "width": "100%",
                            "padding": "10px",
                            "marginBottom": "12px",
                            "border": "1px solid #ddd",
                            "borderRadius": "4px",
                            "boxSizing": "border-box"
                        }}
                    />
                    <input
                        type="password"
                        value={password}
                        onChange={lambda e: any -> None { setPassword(e.target.value); }}
                        placeholder="Password"
                        style={{
                            "width": "100%",
                            "padding": "10px",
                            "marginBottom": "12px",
                            "border": "1px solid #ddd",
                            "borderRadius": "4px",
                            "boxSizing": "border-box"
                        }}
                    />
                    {(<div style={{
                            "color": "#dc2626",
                            "fontSize": "14px",
                            "marginBottom": "12px"
                        }}>{error}</div>) if error else None}
                    <button
                        type="submit"
                        style={{
                            "width": "100%",
                            "padding": "10px",
                            "background": "#667eea",
                            "color": "#ffffff",
                            "border": "none",
                            "borderRadius": "4px",
                            "cursor": "pointer",
                            "fontWeight": "600"
                        }}
                    >Sign Up</button>
                </form>
                <p style={{"textAlign": "center", "marginTop": "16px", "fontSize": "14px"}}>
                    Have an account? <Link to="/login">Login</Link>
                </p>
            </div>
        </div>;
    }

    # Dashboard Page (Protected)
    def DashboardPage() -> any {
        return <div style={{
            "minHeight": "calc(100vh - 56px)",
            "padding": "40px 20px",
            "background": "#f5f5f5"
        }}>
            <div style={{
                "maxWidth": "800px",
                "margin": "0 auto",
                "background": "#ffffff",
                "padding": "40px",
                "borderRadius": "8px",
                "boxShadow": "0 2px 8px rgba(0,0,0,0.1)"
            }}>
                <h1 style={{"marginBottom": "16px"}}>Welcome to Your Dashboard</h1>
                <p style={{"color": "#666", "lineHeight": "1.6"}}>
                    You are now logged in and can access protected content.
                </p>
                <p style={{"color": "#666", "lineHeight": "1.6", "marginTop": "16px"}}>
                    This is a simple dashboard page demonstrating authentication 
                    with routing in Jac. You can add your own content and functionality here.
                </p>
            </div>
        </div>;
    }

    # Main App with Routing
    def app() -> any {
        useEffect(lambda -> None {
            if jacIsLoggedIn() {
                window.location.hash = "#/dashboard";
            }
        }, []);
        return <Router defaultRoute="/login">
            <div style={{
                "fontFamily": "system-ui, -apple-system, sans-serif",
                "minHeight": "100vh"
            }}>
                <Navigation />
                <Routes>
                    <Route path="/login" component={LoginPage} />
                    <Route path="/signup" component={SignupPage} />
                    <Route path="/dashboard" component={DashboardPage} guard={jacIsLoggedIn} />
                </Routes>
            </div>
        </Router>;
    }
}
