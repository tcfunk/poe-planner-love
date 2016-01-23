require 'colors'

Node = {}
Node.__index = Node

-- Define node types so we can use switch
-- statements rather that if/else's
Node.NT_COMMON   = 1
Node.NT_NOTABLE  = 2
Node.NT_MASTERY  = 3
Node.NT_KEYSTONE = 4
Node.NT_START    = 5
Node.NT_JEWEL    = 6

-- Some contants for drawing
Node.SkillsPerOrbit = {1, 6, 12, 12, 40}
Node.OrbitRadii = {0, 81.5, 163, 326, 489}
Node.Radii = {51, 70, 107, 109, 200, 51}

Node.ActiveSkillsheets = {
  "normalActive",
  "notableActive",
  "mastery",
  "keystoneActive",
  "normalActive",
  "normalActive",
}

Node.InactiveSkillsheets = {
  "normalInactive",
  "notableInactive",
  "mastery",
  "keystoneInactive",
  "normalInactive",
  "normalInactive",
}

Node.InactiveSkillFrameNames = {
  "PSSkillFrame",
  "NotableFrameUnallocated",
  nil,
  "KeystoneFrameUnallocated",
  nil,
  "JewelFrameUnallocated"
}

Node.ActiveSkillFrames = {
  "PSSkillFrameActive",
  "NotableFrameAllocated",
  nil,
  "KeystoneFrameAllocated",
  nil,
  "JewelFrameAllocated"
}

-- Translate start classes
Node.classframes = {
  'centerscion',
  'centermarauder',
  'centerranger',
  'centerwitch',
  'centerduelist',
  'centertemplar',
  'centershadow',
}

function Node.arc(node)
  return 2 * math.pi * node.orbitIndex / Node.SkillsPerOrbit[node.orbit]
end

function Node.nodePosition(node)
  local x = 0
  local y = 0

  if node.group ~= nil then
    local r = Node.OrbitRadii[node.orbit]
    local a = Node.arc(node)

    x = node.group.position.x - r * math.sin(-a)
    y = node.group.position.y - r * math.cos(-a)
  end

  return {x = x, y = y}
end

-- Create Node from json information, translating
-- some of the parameters to more human-readable names
function Node.create(data, group)
  local node = {group = group}
  setmetatable(node, Node)

  -- Set non-computed attributes
  node.id         = tonumber(data.id)
  node.gid        = tonumber(data.g)
  node.orbit      = tonumber(data.o) + 1 -- lua arrays are not 0-indexed
  node.orbitIndex = tonumber(data.oidx)
  node.icon       = data.icon
  node.out        = data.out
  node.neighbors  = data.out
  node.name       = data.dn
  node.startPositionClasses = data.spc

  -- Set nodes to active for now, until we get further along. it's too hard
  -- to see everything otherwise
  node.active = false

  -- Set node type
  if #node.startPositionClasses ~= 0 then
    node.type = Node.NT_START
    if node.startPositionClasses[1]+1 == activeClass then
      node.active = true
    end
  elseif data.m then
    node.type = Node.NT_MASTERY
  elseif data["not"] then
    node.type = Node.NT_NOTABLE
  elseif data.ks then
    node.type = Node.NT_KEYSTONE
  elseif data.dn == 'Jewel Socket' then
    node.type = Node.NT_JEWEL
  else
    node.type = Node.NT_COMMON
  end

  -- Set radius based on node type
  node.radius = Node.Radii[node.type]

  -- Compute position now, rather than on-the-fly later
  -- since the nodes aren't moving anywhere
  node.position = Node.nodePosition(node)

  return node
end

-- Updates viewport as well as visible boundaries fer draw-call checking
function Node:setQuad(quad)
  self.imageQuad = quad
  local _,_,w,h = quad:getViewport()

  self.visibleQuad = {
    top    = self.position.y - h/2,
    bottom = self.position.y + h/2,
    left   = self.position.x - w/2,
    right  = self.position.x + w/2
  }
end

function Node:isVisible(tx, ty)
  return (self.visibleQuad.top + ty) < scaledHeight and
         (self.visibleQuad.bottom + ty) > 0 and
         (self.visibleQuad.left + tx) < scaledWidth and
         (self.visibleQuad.right + tx) > 0
end

-- Renders the node (love2d-style)
function Node:draw(tx, ty)
  if self:isVisible(tx, ty) then
    local sheet = self.active and self.activeSheet or self.inactiveSheet
    love.graphics.draw(sheet, self.imageQuad, self.visibleQuad.left, self.visibleQuad.top)
    if visibleNodes[self.id] == nil then
      visibleNodes[self.id] = self
    end

    self:drawFrame()
  end
end

function Node:drawFrame()
  if #self.startPositionClasses > 0 then
    local bg = images['PSGroupBackground3']
    local w, h = bg:getDimensions()
    love.graphics.draw(bg, self.position.x - w/2, self.position.y - h)
    love.graphics.draw(bg, self.position.x + w/2, self.position.y + h, math.pi)

    -- Draw all as inactive fer now
    -- @TODO: Stop doing that.
    local spc = self.startPositionClasses[1] + 1 -- there is only ever one
    local sprite = images['PSStartNodeBackgroundInactive']
    if spc == activeClass then
      sprite = images[Node.classframes[spc]]
    end
    w, h = sprite:getDimensions()
    love.graphics.draw(sprite, self.position.x - w/2, self.position.y - h/2)
  else
    local sheetName = self.active and Node.ActiveSkillFrames[self.type] or Node.InactiveSkillFrameNames[self.type]
    if sheetName ~= nil then
      local w, h = images[sheetName]:getDimensions()
      love.graphics.draw(images[sheetName], self.position.x - w/2, self.position.y - h/2)
    end
  end
end

function Node:drawConnections()
    for _, nid in pairs(self.out) do
      local other = nodes[nid]
      local color = (self.active and other.active) and activeConnector or inactiveConnector
      love.graphics.setColor(color)
      if (self.group.id ~= other.group.id) or (self.orbit ~= other.orbit) then
        self:drawConnection(other)
      else
        self:drawArcedConnection(other)
      end
      clearColor()
    end
end

function Node:drawConnection(other)
  -- @TODO: (low priority) Draw line graphics instead of line objects?
  love.graphics.line(self.position.x, self.position.y, other.position.x, other.position.y)
end

function Node:drawArcedConnection(other)
  local startAngle = Node.arc(self)
  local endAngle = Node.arc(other)

  if startAngle > endAngle then
    startAngle, endAngle = endAngle, startAngle
  end
  local delta = endAngle - startAngle

  if delta > math.pi then
    local c = 2*math.pi - delta
    endAngle = startAngle
    startAngle = endAngle + c
    delta = c
  end

  local center = self.group.position
  local radius = Node.OrbitRadii[self.orbit]
  local steps = math.ceil(30*(delta/(math.pi*2)))
  local stepSize = delta/steps

  local points = {}
  local radians = 0
  endAngle = endAngle - math.pi/2
  for i=0,steps do
    radians = endAngle - stepSize*i
    table.insert(points, radius*math.cos(radians)+center.x)
    table.insert(points, radius*math.sin(radians)+center.y)
  end

  if steps < 0 or #points < 0 then
    return
  end

  love.graphics.line(points)
end

function Node:hasActiveNeighbors()
  -- @TODO: This will likely need refactored once we work once
  -- allowing for proper node deactivation
  for _, nid in pairs(self.neighbors) do
    if nodes[nid].active then
      return true
    end
  end
  return false
end

return Node
