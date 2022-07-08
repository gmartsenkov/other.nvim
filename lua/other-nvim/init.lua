-- The module itself
local M = {}

local options = {}

-- Helper functions to pick files from an popup
local window = require("other-nvim.helper.window")

-- Include utils
local util = require("other-nvim.helper.util")

-- Include the builtin mappings and transformers
local builtinMappings = require("other-nvim.builtin.mappings")
local transformers = require("other-nvim.builtin.transformers")

-- default settings
local defaults = {

	-- by default there are no mappings enabled
	mappings = {},

	-- default transformers
	transformers = {
		camelToKebap = transformers.camelToKebap,
		kebapToCamel = transformers.kebapToCamel,
	},

	-- When a mapping requires an initial selection of the other file, this setting controls,
	-- wether the selection should be remembered for the current user session.
	-- When this option is set to false reference between the two buffers are never saved.
	-- Existing references can be removed on the buffer with :OtherClear
	rememberBuffers = true,
}

-- Find the potential other file(s)
-- Returns a table of matches.
local findOther = function(filename, context)
	local matches = {}
	-- iterate over all the mapping to check if the filename matches against any "pattern")
	for _, mapping in pairs(options.mappings or {}) do
		local match

		if mapping.context == context or context == nil then
			match = filename:match(mapping.pattern)
		end

		if match ~= nil then
			-- if we have a match, optionally transforn the match
			if mapping.transformer ~= nil then
				local transformedMatch = defaults.transformers[mapping.transformer](match)
				filename, _ = filename:gsub(util.escape_pattern(match), transformedMatch)
			end

			-- return (transformed) match with "target"
			local result, _ = filename:gsub(mapping.pattern, mapping.target)

			-- get a list of candidates based on the transformed match.
			-- additional glob-patterns in the target are respected
			-- return vim.fn.glob(result, true, true)
			if vim.fn.isdirectory(result) then
				result = result .. "*"
			end

			local mappingMatches = vim.fn.glob(result, true, true)
			for _, value in pairs(mappingMatches) do

				-- check wether the file is already added to the result
				local found = false
				for _, checkValue in pairs(matches) do
					if checkValue.filename == value then
						found = true
					end
				end

				if (found == false and filename ~= value) then
					table.insert(matches, { context = mapping.context, filename = value })
				end
			end
		end
	end
	return matches
end

local flattenMapping = function(mapping, result)
	-- multiple patterns for a mapping
	if type(mapping.target) == "table" then
		for _, t in pairs(mapping.target) do
			local m = vim.deepcopy(mapping)

			if type(t) == "string" then
				m.target = t
			end
			if type(t) == "table" then
				for key, tv in pairs(t) do
					m[key] = tv
				end
			end
			table.insert(result, m)
		end
	else
		table.insert(result, mapping)
	end
	return result
end

-- Resolve string based builtinMappings
local resolveBuiltinMappings = function(mappings)
	local result = {}
	if mappings ~= nil then
		for _, mapping in pairs(mappings) do
			if type(mapping) == "string" then
				if builtinMappings[mapping] ~= nil then
					for _, biM in pairs(builtinMappings[mapping]) do
						result = flattenMapping(biM, result)
					end
				end
			else
				result = flattenMapping(mapping, result)
			end
		end
	end
	return result
end

M.setOtherFileToBuffer = function(otherFile, bufferHandle)
	if options.rememberBuffers == true then
		if otherFile then
			vim.api.nvim_buf_set_var(bufferHandle, "onv_otherFile", otherFile)
		end
	end
end

local getOtherFileFromBuffer = function()
	return vim.b.onv_otherFile
end

-- Actual opening
local open = function(context, openCommand)
	local fileFromBuffer = nil

	-- only check for remembered value if no context is given.
	if (context == nil) then
		fileFromBuffer = getOtherFileFromBuffer()
	end
	-- when we had a match before, open that
	if fileFromBuffer then
		vim.api.nvim_command(":" .. openCommand .. " " .. fileFromBuffer)
	else
		local matches = findOther(vim.api.nvim_buf_get_name(0), context or nil)
		local matchesCount = #matches
		if matchesCount > 0 then
			-- when dealing with a single file -> just open it
			if matchesCount == 1 then
				M.setOtherFileToBuffer(matches[1].filename, vim.api.nvim_get_current_buf())
				vim.api.nvim_command(":" .. openCommand .. " " .. matches[1].filename)
			else
				-- otherwise open a window to pick a file
				window.open_window(matches, M, vim.api.nvim_get_current_buf())
			end
		else
			print("No 'other' file found.")
		end
	end
end

-- -- -- -- -- -- -- -- -- -- PUBLIC -- -- -- -- -- -- -- -- --

-- Default setup method
M.setup = function(opts)
	opts.mappings = resolveBuiltinMappings(opts.mappings)
	options = vim.tbl_deep_extend("force", {}, defaults, opts or {})
end

-- Trying to open another file
M.open = function(context)
	open(context, "e")
end

-- Trying to open another file in split
M.openSplit = function(context)
	open(context, "sp")
end

-- Trying to open another file in vertical split
M.openVSplit = function(context)
	open(context, "vs")
end

-- return the currently set options
M.getOptions = function()
	return options
end

-- Removing the memorized "other" file from the current buffer
M.clear = function()
	vim.b.onv_otherFile = nil
end

M.findOther = function(context)
        return findOther(vim.api.nvim_buf_get_name(0), context or nil)
end

return M
