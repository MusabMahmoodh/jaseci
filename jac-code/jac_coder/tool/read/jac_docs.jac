import os;
import re;
import sys;

import from jac_coder.infra.config { get_data_dir }
import from jac_coder.util.tool_output { truncate_output, tool_status, tool_end }
import from jac_coder.runtime.events { track_jac_docs_call }


"""Search Jac documentation by keyword."""
def jac_docs(query: str, max_results: int = 2) -> str;

sem jac_docs = "Search the Jac language documentation. Returns matching sections from reference docs, example apps, and syntax rules. ALWAYS call this before writing ANY Jac code — your training data has outdated syntax. Available topics: reference/syntax (types, control flow, imports), reference/osp (nodes, edges, walkers, graph), reference/frontend (components, state, effects, sv import, @jac/runtime), reference/backend (endpoints, persistence, auth, routing), reference/ai (by llm, tools, ReAct), reference/pitfalls (runtime crashes, guards, common errors), examples/todo_app, examples/blog_app, examples/core_patterns, examples/ai_agent, rules/core_jac (syntax pitfalls), rules/fullstack (frontend+backend patterns), rules/workflow (build order, validation, project creation).";
sem jac_docs.query = "Search query — use descriptive terms like 'walker entry point', 'sv import pattern', 'frontend state effects', 'node edge connect', 'by llm tools'. Broader queries return more useful results.";
