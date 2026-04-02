#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <regex>
#include <stack>
#include <set>

// Escape a string for safe JSON embedding
std::string json_escape(const std::string& s) {
    std::string out;
    out.reserve(s.size());
    for (char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n";  break;
            case '\r': out += "\\r";  break;
            case '\t': out += "\\t";  break;
            default:   out += c;      break;
        }
    }
    return out;
}

// Trim whitespace from both ends
std::string trim(const std::string& s) {
    size_t start = s.find_first_not_of(" \t\r\n");
    size_t end   = s.find_last_not_of(" \t\r\n");
    return (start == std::string::npos) ? "" : s.substr(start, end - start + 1);
}

struct Issue {
    int         line_number;
    std::string issue;
    std::string code_snippet;
};

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: liquid_analyzer <file_path>\n";
        return 1;
    }

    std::ifstream file(argv[1]);
    if (!file.is_open()) {
        std::cerr << "Error: cannot open file '" << argv[1] << "'\n";
        return 1;
    }

    // {% for VAR in COLLECTION %} — handles multi-level paths like collections.frontpage.products
    // Group 1 = loop variable
    // Group 2 = first segment of the collection path (may be a loop variable)
    // Group 3 = remainder of dotted path, e.g. ".frontpage.products" or ".metafields" (may be empty)
    std::regex for_re(R"(\{%-?\s*for\s+(\w+)\s+in\s+(\w+)((?:\.\w+)+)?\s*-?%\})");

    // {% endfor %}
    std::regex endfor_re(R"(\{%-?\s*endfor\s*-?%\})");

    // {{ VAR.prop ... }} — object property output
    // Group 1 = object name
    std::regex output_re(R"(\{\{-?\s*(\w+)\.\w+.*?-?\}\})");

    std::vector<std::string> lines;
    std::string ln;
    while (std::getline(file, ln)) {
        lines.push_back(ln);
    }
    file.close();

    std::vector<Issue> issues;

    // Stack: each entry is the loop variable name introduced at that depth.
    // We also maintain the set of all active loop variables for O(1) lookup.
    std::stack<std::string> loop_var_stack;  // preserves order / depth count
    std::set<std::string>   active_loop_vars;
    int loop_depth = 0;  // current nesting level (0 = outside all loops)

    for (int i = 0; i < (int)lines.size(); i++) {
        const std::string& line = lines[i];
        int line_no = i + 1;

        // --- Check for {% for %} openers ---
        auto for_it  = std::sregex_iterator(line.begin(), line.end(), for_re);
        auto for_end = std::sregex_iterator();

        for (auto it = for_it; it != for_end; ++it) {
            std::smatch m = *it;
            std::string loop_var  = m[1].str();   // e.g. "metafield"
            std::string coll_obj  = m[2].str();   // e.g. "product" or "collections"
            std::string coll_rest = m[3].str();   // e.g. ".metafields" or ".frontpage.products"

            bool is_n1 = false;

            if (!coll_rest.empty()) {
                // {% for x in obj.something... %} — N+1 if obj is an active loop variable
                if (active_loop_vars.count(coll_obj)) {
                    is_n1 = true;
                }
            }

            if (is_n1) {
                issues.push_back({line_no, "N+1 query detected", trim(line)});
            }

            // Push loop variable onto the stack regardless
            loop_var_stack.push(loop_var);
            active_loop_vars.insert(loop_var);
            loop_depth++;
        }

        // --- Check for {{ var.prop }} output expressions (only inside NESTED loops) ---
        // depth >= 2 means we're inside at least two levels of for loops — genuine N+1 context
        if (loop_depth >= 2) {
            auto out_it  = std::sregex_iterator(line.begin(), line.end(), output_re);
            auto out_end = std::sregex_iterator();

            for (auto it = out_it; it != out_end; ++it) {
                std::smatch m  = *it;
                std::string obj = m[1].str();

                // Flag if the object is an active loop variable — every access
                // inside a loop body that touches a loop var's property is
                // a potential lazy-load / N+1.
                if (active_loop_vars.count(obj)) {
                    // Avoid double-reporting lines already flagged (e.g. for opener)
                    bool already = false;
                    for (auto& iss : issues) {
                        if (iss.line_number == line_no) { already = true; break; }
                    }
                    if (!already) {
                        issues.push_back({line_no, "N+1 query detected", trim(line)});
                        break; // one report per line is enough
                    }
                }
            }
        }

        // --- Process {% endfor %} closers ---
        auto end_it  = std::sregex_iterator(line.begin(), line.end(), endfor_re);
        auto end_end = std::sregex_iterator();

        for (auto it = end_it; it != end_end; ++it) {
            if (!loop_var_stack.empty()) {
                std::string var = loop_var_stack.top();
                loop_var_stack.pop();
                // Only remove from active set if no other level still uses this var name
                // (edge case: same var name reused at different depths — keep if still in stack)
                bool still_active = false;
                std::stack<std::string> tmp = loop_var_stack;
                while (!tmp.empty()) {
                    if (tmp.top() == var) { still_active = true; break; }
                    tmp.pop();
                }
                if (!still_active) active_loop_vars.erase(var);
                loop_depth--;
                if (loop_depth < 0) loop_depth = 0;
            }
        }
    }

    // Output JSON to stdout
    std::cout << "[";
    for (int i = 0; i < (int)issues.size(); i++) {
        if (i > 0) std::cout << ",";
        std::cout << "{"
                  << "\"line_number\":" << issues[i].line_number << ","
                  << "\"issue\":\""     << json_escape(issues[i].issue) << "\","
                  << "\"code_snippet\":\"" << json_escape(issues[i].code_snippet) << "\""
                  << "}";
    }
    std::cout << "]" << std::endl;

    return 0;
}
