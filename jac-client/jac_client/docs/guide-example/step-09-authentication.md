# Step 9: Adding Authentication

In this step, you'll learn how to add user authentication (signup and login) to your todo app.

## Why Authentication?

Without authentication:
- Anyone can see anyone's todos
- No way to identify users
- Can't have private data

With authentication:
- Each user has their own account
- Users only see their own todos
- Secure and private

**Python analogy:**

```python
# Without auth
@app.route("/todos")
def get_todos():
    return all_todos  # Everyone sees everything!

# With auth
@app.route("/todos")
@login_required
def get_todos():
    user = get_current_user()
    return user.todos  # Only your todos!
```

## Jac's Built-in Authentication

Jac provides authentication utilities out of the box:

```jac
cl import from "@jac-client/utils" {
    jacLogin,        # Log user in
    jacSignup,       # Create new account
    jacLogout,       # Log user out
    jacIsLoggedIn    # Check if logged in
}
```

No need to:
- Set up JWT tokens
- Create user tables
- Hash passwords
- Manage sessions

**Jac handles it all!**

## Creating a useAuth Hook

Let's create a custom hook for authentication (like a helper class):

```jac
cl import from react {useState}
cl import from "@jac-client/utils" {
    jacLogin,
    jacSignup,
    jacLogout,
    jacIsLoggedIn
}

cl {
    def useAuth() -> dict {
        # Login function
        async def login(username: str, password: str) -> dict {
            try {
                result = await jacLogin(username, password);
                if result {
                    return {"success": True, "data": result, "error": None};
                }
                return {"success": False, "error": "Invalid credentials"};
            } except Exception as err {
                return {"success": False, "error": "Invalid credentials"};
            }
        }
        
        # Signup function
        async def signup(username: str, password: str, confirmPassword: str) -> dict {
            # Validate passwords match
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
        
        # Logout function
        def logout() -> None {
            jacLogout();
        }
        
        # Check if authenticated
        def isAuthenticated() -> bool {
            return jacIsLoggedIn();
        }
        
        # Return all auth functions
        return {
            "login": login,
            "signup": signup,
            "logout": logout,
            "isAuthenticated": isAuthenticated
        };
    }
}
```

**What this does:**
- Wraps Jac's auth functions
- Provides consistent error handling
- Returns user-friendly responses
- Easy to use in any component

**Python analogy:**

```python
class AuthService:
    def login(self, username, password):
        # Handle login
        pass
    
    def signup(self, username, password):
        # Handle signup
        pass
    
    def logout(self):
        # Handle logout
        pass
    
    def is_authenticated(self):
        # Check if logged in
        pass
```

## Creating the Login Page

Let's build a complete login form:

```jac
cl import from react {useState, useEffect}
cl import from "@jac-client/utils" {useNavigate, jacIsLoggedIn}

cl {
    def LoginPage() -> any {
        let [state, setState] = useState({
            "username": "",
            "password": "",
            "loading": False,
            "error": ""
        });
        
        let navigate = useNavigate();
        let auth = useAuth();
        
        # Redirect if already logged in
        useEffect(lambda -> None {
            if jacIsLoggedIn() {
                navigate("/dashboard");
            }
        }, []);
        
        async def handleSubmit(event: any) -> None {
            event.preventDefault();  # Prevent form submission reload
            
            # Set loading state
            let current = state;
            setState({
                "username": current["username"],
                "password": current["password"],
                "loading": True,
                "error": ""
            });
            
            try {
                # Attempt login
                let result = await auth["login"](
                    current["username"],
                    current["password"]
                );
                
                if result["success"] {
                    # Success - redirect to dashboard
                    navigate("/dashboard");
                } else {
                    # Failed - show error
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
            "padding": "48px 16px",
            "backgroundColor": "#f9fafb",
            "minHeight": "100vh"
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
                
                {/* Error Message */}
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
                
                {/* Login Form */}
                <form onSubmit={handleSubmit} style={{
                    "display": "flex",
                    "flexDirection": "column",
                    "gap": "16px"
                }}>
                    {/* Username */}
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
                    
                    {/* Password */}
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
                    
                    {/* Submit Button */}
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
                
                {/* Signup Link */}
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
}
```

## Creating the Signup Page

```jac
cl {
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
        
        # Redirect if already logged in
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
                    # Success - redirect to dashboard
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
            "maxWidth": "420px",
            "margin": "48px auto",
            "padding": "32px",
            "backgroundColor": "#ffffff",
            "borderRadius": "16px",
            "boxShadow": "0 20px 55px rgba(15,23,42,0.12)"
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
            
            {/* Error */}
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
                {/* Username */}
                <label>
                    <span style={{"fontSize": "14px", "fontWeight": "600"}}>
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
                            "width": "100%",
                            "padding": "12px",
                            "borderRadius": "8px",
                            "border": "1px solid #e2e8f0"
                        }}
                        required={True}
                    />
                </label>
                
                {/* Password */}
                <label>
                    <span style={{"fontSize": "14px", "fontWeight": "600"}}>
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
                            "width": "100%",
                            "padding": "12px",
                            "borderRadius": "8px",
                            "border": "1px solid #e2e8f0"
                        }}
                        required={True}
                    />
                </label>
                
                {/* Confirm Password */}
                <label>
                    <span style={{"fontSize": "14px", "fontWeight": "600"}}>
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
                            "width": "100%",
                            "padding": "12px",
                            "borderRadius": "8px",
                            "border": "1px solid #e2e8f0"
                        }}
                        required={True}
                    />
                </label>
                
                <button
                    type="submit"
                    disabled={state["loading"]}
                    style={{
                        "padding": "12px",
                        "borderRadius": "8px",
                        "backgroundColor": "#22c55e",
                        "color": "#ffffff",
                        "fontWeight": "600",
                        "border": "none",
                        "cursor": (("not-allowed" if state["loading"] else "pointer")),
                        "opacity": ((0.6 if state["loading"] else 1))
                    }}
                >
                    {(("Creating account..." if state["loading"] else "Create Account"))}
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
        </div>;
    }
}
```

## Protected Dashboard

Now let's update the dashboard to require authentication:

```jac
cl import from "@jac-client/utils" {Router, Routes, Route, jacIsLoggedIn}

cl {
    def DashboardPage() -> any {
        # Your todo app logic here...
        return <div>
            <h1>My Todos</h1>
            {/* Todo app UI */}
        </div>;
    }

    def app() -> any {
        return <Router defaultRoute="/login">
            <Routes>
                <Route path="/login" component={LoginPage} />
                <Route path="/signup" component={SignupPage} />
                
                {/* Protected route */}
                <Route 
                    path="/dashboard" 
                    component={DashboardPage}
                    guard={jacIsLoggedIn}  # Requires login!
                />
            </Routes>
        </Router>;
    }
}
```

**What happens:**
- If not logged in → Redirected to `/login`
- If logged in → Dashboard shows

## Adding Logout

Let's add a logout button in the header:

```jac
cl {
    def AppHeader() -> any {
        let navigate = useNavigate();
        let auth = useAuth();
        let isLoggedIn = jacIsLoggedIn();
        
        def handleLogout() -> None {
            auth["logout"]();
            navigate("/login");
        }
        
        return <header style={{
            "backgroundColor": "#ffffff",
            "borderBottom": "1px solid #e5e7eb",
            "padding": "16px 24px"
        }}>
            <div style={{
                "maxWidth": "1080px",
                "margin": "0 auto",
                "display": "flex",
                "justifyContent": "space-between",
                "alignItems": "center"
            }}>
                <h1>Todo App</h1>
                
                {(
                    <button onClick={lambda -> None { handleLogout(); }} style={{
                        "padding": "8px 16px",
                        "backgroundColor": "#ef4444",
                        "color": "white",
                        "border": "none",
                        "borderRadius": "6px",
                        "cursor": "pointer"
                    }}>
                        Logout
                    </button>
                ) if isLoggedIn else (
                    <Link to="/login" style={{
                        "padding": "8px 16px",
                        "backgroundColor": "#3b82f6",
                        "color": "white",
                        "textDecoration": "none",
                        "borderRadius": "6px"
                    }}>
                        Login
                    </Link>
                )}
            </div>
        </header>;
    }
}
```

## Testing Authentication

1. **Start your app:**
   ```bash
   jac serve app.jac
   ```

2. **Create an account:**
   - Go to `/signup`
   - Enter username and password
   - Click "Create Account"
   - Should redirect to dashboard

3. **Test protected route:**
   - Logout
   - Try to visit `/dashboard`
   - Should redirect to `/login`

4. **Login:**
   - Enter credentials
   - Should redirect to dashboard

## User Isolation

The magic: **Each user only sees their own todos!**

```jac
walker read_todos {
    class __specs__ {
        has auth: bool = True;  # This ensures isolation!
    }
    
    can read with `root entry {
        visit [-->(`?Todo)];
    }
    
    can report_todos with exit {
        report here;
    }
}
```

When `auth: bool = True`:
- Jac automatically uses the logged-in user's root node
- User A can't see User B's todos
- No extra code needed!

## Common Authentication Patterns

### Pattern 1: Conditional UI

```jac
def HomePage() -> any {
    let isLoggedIn = jacIsLoggedIn();
    
    return <div>
        {(
            <Link to="/dashboard">Go to Dashboard</Link>
        ) if isLoggedIn else (
            <Link to="/login">Login to Continue</Link>
        )}
    </div>;
}
```

### Pattern 2: Auto-Redirect After Signup

```jac
async def handleSignup() -> None {
    let result = await auth["signup"](username, password, confirm);
    if result["success"] {
        # Auto-login and redirect
        await auth["login"](username, password);
        navigate("/dashboard");
    }
}
```

### Pattern 3: Remember Me (Session Persistence)

Jac automatically handles session persistence - users stay logged in across page refreshes!

## Common Issues

### Issue: Can't login after signup
**Solution**: Make sure signup returns success correctly. Check the response structure.

### Issue: Redirected to login immediately
**Check**: Is `jacIsLoggedIn()` returning `True`? Check browser console for errors.

### Issue: Can access protected route without login
**Check**: Did you add `guard={jacIsLoggedIn}` to the Route?

### Issue: Logout doesn't work
**Solution**: Call `jacLogout()` and then navigate to login page.

## What You Learned

- ✅ Jac's built-in authentication system
- ✅ Creating login and signup forms
- ✅ Using `jacLogin`, `jacSignup`, `jacLogout`, `jacIsLoggedIn`
- ✅ Protected routes with guards
- ✅ User isolation (each user sees only their data)
- ✅ Logout functionality
- ✅ Conditional UI based on auth state

## Next Step

Congratulations! You've learned all the key concepts. Now let's put everything together into the **complete, final app**!

👉 **[Continue to Step 10: Final Integration](./step-10-final.md)**


