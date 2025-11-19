import {__jacJsx, __jacSpawn} from "@jac-client/utils";
import { useState, useEffect } from "react";
import burgerImage from "@jac-client/assets/burger.png";
function app() {
  let [count, setCount] = useState(0);
  useEffect(() => {
    console.log("Count: ", count);
  }, [count]);
  return __jacJsx("div", {"style": {padding: "20px", textAlign: "center", fontFamily: "Arial, sans-serif"}}, [__jacJsx("h1", {}, ["🍔 Import Alias Example"]), __jacJsx("p", {"style": {color: "#666", marginBottom: "20px"}}, ["Using ", __jacJsx("code", {}, ["@jac-client/assets"]), " alias to import assets"]), __jacJsx("img", {"src": burgerImage, "alt": "Delicious Burger", "style": {width: "200px", height: "auto", margin: "20px 0", borderRadius: "10px", boxShadow: "0 4px 8px rgba(0,0,0,0.2)"}}, []), __jacJsx("p", {"style": {fontSize: "18px", margin: "20px 0"}}, ["You've clicked the burger ", __jacJsx("strong", {}, [count]), " times!"]), __jacJsx("button", {"onClick": e => {
    setCount(count + 1);
  }, "style": {padding: "10px 20px", fontSize: "16px", backgroundColor: "#ff6b35", color: "white", border: "none", borderRadius: "5px", cursor: "pointer", boxShadow: "0 2px 4px rgba(0,0,0,0.2)"}}, ["Click the Burger! 🍔"]), __jacJsx("div", {"style": {marginTop: "30px", padding: "15px", backgroundColor: "#f5f5f5", borderRadius: "5px", fontSize: "12px", textAlign: "left", maxWidth: "600px", margin: "30px auto"}}, [__jacJsx("strong", {}, ["How it works:"]), __jacJsx("ul", {"style": {marginTop: "10px", paddingLeft: "20px"}}, [__jacJsx("li", {}, ["Import using: ", __jacJsx("code", {}, ["cl import from '@jac-client/assets/burger.png'"])]), __jacJsx("li", {}, ["Vite processes the import and generates optimized URLs"]), __jacJsx("li", {}, ["Assets are automatically copied from ", __jacJsx("code", {}, ["assets/"]), " to ", __jacJsx("code", {}, ["src/assets/"]), " during build"]), __jacJsx("li", {}, ["Automatic hash generation for cache busting"])])])]);
}
export { app };
