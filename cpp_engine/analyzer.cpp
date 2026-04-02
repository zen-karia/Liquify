#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <regex>
#include <stack>
#include <set>

// Load lazy-loaded property names from a config file next to the binary.
// Falls back to a sensible default set if the file is not found.
std::set<std::string> load_lazy_props(const std::string& binary_path) {
    std::set<std::string> props;

    // Derive config path: same directory as the binary
    std::string dir = binary_path;
    size_t slash = dir.find_last_of("/\\");
    if (slash != std::string::npos) dir = dir.substr(0, slash + 1);
    else dir = "./";

    std::ifstream cfg(dir + "lazy_props.txt");
    if (cfg.is_open()) {
        std::string line;
        while (std::getline(cfg, line)) {
            // Strip whitespace
            size_t s = line.find_first_not_of(" \t\r\n");
            if (s == std::string::npos) continue;
            line = line.substr(s, line.find_last_not_of(" \t\r\n") - s + 1);
            // Skip comments and empty lines
            if (line.empty() || line[0] == '#') continue;
            props.insert(line);
        }
        return props;
    }

    // Default fallback if config file not found
    return {
        "metafields", "variants", "images", "media",
        "collections", "tags", "options", "selling_plan_groups",
        "metaobjects", "files", "reviews", "related_products"
    };
}

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

// Check if a line was already flagged at this line number
bool already_flagged(const std::vector<std::pair<int,std::string>>& issues, int line_no) {
    for (auto& p : issues) {
        if (p.first == line_no) return true;
    }
    return false;
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

    // Load lazy props from config file next to the binary
    const std::set<std::string> LAZY_PROPS = load_lazy_props(argv[0]);

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

    // {{ VAR.prop ... }} — captures object name (group 1) and property (group 2)
    std::regex output_re(R"(\{\{-?\s*(\w+)\.(\w+).*?-?\}\})");

    std::vector<std::string> lines;
    std::string ln;
    while (std::getline(file, ln)) {
        lines.push_back(ln);
    }
    file.close();

    std::vector<Issue> issues;

    // Stack: each entry is the loop variable name introduced at that depth.
    // We also maintain the set of all active loop variables for O(1) lookup.
    std::stack<std::string> loop_var_stack;
    std::set<std::string>   active_loop_vars;
    int loop_depth = 0;

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

            loop_var_stack.push(loop_var);
            active_loop_vars.insert(loop_var);
            loop_depth++;
        }

        // --- Check for {{ var.prop }} output expressions ---
        // Rule A: depth >= 2 — any loop var property access in a nested loop
        // Rule B: depth >= 1 — loop var accessing a KNOWN lazy-loaded Shopify property
        if (loop_depth >= 1) {
            auto out_it  = std::sregex_iterator(line.begin(), line.end(), output_re);
            auto out_end = std::sregex_iterator();

            for (auto it = out_it; it != out_end; ++it) {
                std::smatch m    = *it;
                std::string obj  = m[1].str();   // e.g. "product"
                std::string prop = m[2].str();   // e.g. "metafields"

                bool is_loop_var  = active_loop_vars.count(obj) > 0;
                bool is_lazy_prop = LAZY_PROPS.count(prop) > 0;

                bool flag = false;
                if (is_loop_var && loop_depth >= 2)  flag = true;  // Rule A
                if (is_loop_var && is_lazy_prop)      flag = true;  // Rule B (any depth)

                if (flag) {
                    // Avoid double-reporting lines already flagged
                    bool already = false;
                    for (auto& iss : issues) {
                        if (iss.line_number == line_no) { already = true; break; }
                    }
                    if (!already) {
                        issues.push_back({line_no, "N+1 query detected", trim(line)});
                        break;
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
