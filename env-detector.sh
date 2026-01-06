#!/bin/bash

# ============================================
# Script: env-detective-fixed.sh
# Description: ردیابی env variables - نسخه ساده و کارا
# Usage: ./env-detective-fixed.sh [directory]
# ============================================

set -e

# تنظیم رنگ‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

TARGET_DIR="${1:-.}"

echo -e "${PURPLE}🕵️  ENV DETECTIVE - Simple Version${NC}"
echo -e "${PURPLE}===================================${NC}"
echo ""

# بررسی وجود دایرکتوری
if [ ! -d "$TARGET_DIR" ]; then
    echo -e "${RED}❌ Directory not found: $TARGET_DIR${NC}"
    exit 1
fi

# تشخیص ساده نوع پروژه
detect_project() {
    if [ -f "$TARGET_DIR/package.json" ]; then
        if grep -q "next" "$TARGET_DIR/package.json"; then
            echo "Next.js"
        elif grep -q "react" "$TARGET_DIR/package.json"; then
            echo "React"
        elif grep -q "express" "$TARGET_DIR/package.json"; then
            echo "Express.js"
        else
            echo "Node.js"
        fi
    elif [ -f "$TARGET_DIR/pom.xml" ]; then
        echo "Java"
    elif [ -f "$TARGET_DIR/composer.json" ]; then
        echo "PHP"
    elif [ -f "$TARGET_DIR/requirements.txt" ]; then
        echo "Python"
    else
        echo "Unknown"
    fi
}

PROJECT_TYPE=$(detect_project)
echo -e "${BLUE}📁 Directory: $TARGET_DIR${NC}"
echo -e "${BLUE}🏗️  Project Type: $PROJECT_TYPE${NC}"
echo ""

# جستجوی env variables
echo -e "${GREEN}🔍 Scanning for environment variables...${NC}"

# فایل موقت برای ذخیره نتایج
TEMP_FILE=$(mktemp)

# جستجو در فایل‌های JavaScript/TypeScript
find "$TARGET_DIR" -type f \( -name "*.js" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" \) \
    ! -path "*/node_modules/*" \
    ! -path "*/dist/*" \
    ! -path "*/build/*" 2>/dev/null | while read -r file; do
    
    # جستجوی الگوهای مختلف
    grep -n -E "(process\.env\.[A-Za-z_][A-Za-z0-9_]*|REACT_APP_[A-Za-z_][A-Za-z0-9_]*|NEXT_PUBLIC_[A-Za-z_][A-Za-z0-9_]*|VITE_[A-Za-z_][A-Za-z0-9_]*)" "$file" 2>/dev/null | \
    while read -r line; do
        # استخراج نام متغیر
        if echo "$line" | grep -q "process.env"; then
            var_name=$(echo "$line" | grep -o "process\.env\.[A-Za-z_][A-Za-z0-9_]*" | cut -d. -f3)
        elif echo "$line" | grep -q "REACT_APP"; then
            var_name=$(echo "$line" | grep -o "REACT_APP_[A-Za-z_][A-Za-z0-9_]*")
        elif echo "$line" | grep -q "NEXT_PUBLIC"; then
            var_name=$(echo "$line" | grep -o "NEXT_PUBLIC_[A-Za-z_][A-Za-z0-9_]*")
        elif echo "$line" | grep -q "VITE_"; then
            var_name=$(echo "$line" | grep -o "VITE_[A-Za-z_][A-Za-z0-9_]*")
        fi
        
        if [ ! -z "$var_name" ]; then
            echo "$var_name|$file|$line" >> "$TEMP_FILE"
        fi
    done
done

# جستجو در Dockerfile
find "$TARGET_DIR" -type f \( -name "Dockerfile*" -o -name "docker-compose*.yml" \) \
    ! -path "*/node_modules/*" 2>/dev/null | while read -r file; do
    
    grep -n -E "ENV [A-Za-z_][A-Za-z0-9_]*" "$file" 2>/dev/null | \
    while read -r line; do
        var_name=$(echo "$line" | grep -o "ENV [A-Za-z_][A-Za-z0-9_]*" | cut -d' ' -f2)
        if [ ! -z "$var_name" ]; then
            echo "$var_name|$file|$line" >> "$TEMP_FILE"
        fi
    done
done

# جستجو در فایل‌های env
find "$TARGET_DIR" -type f -name ".env*" ! -name "*.example" ! -name "*.sample" 2>/dev/null | while read -r file; do
    grep -n -E "^[A-Za-z_][A-Za-z0-9_]*=" "$file" 2>/dev/null | \
    while read -r line; do
        var_name=$(echo "$line" | cut -d= -f1)
        if [ ! -z "$var_name" ]; then
            echo "$var_name|$file|$line" >> "$TEMP_FILE"
        fi
    done
done

# خواندن و پردازش نتایج
if [ -s "$TEMP_FILE" ]; then
    # استخراج unique variables
    UNIQUE_VARS=$(cut -d'|' -f1 "$TEMP_FILE" | sort -u)
    VAR_COUNT=$(echo "$UNIQUE_VARS" | wc -l)
    
    echo -e "${GREEN}✅ Found $VAR_COUNT unique environment variables${NC}"
    echo ""
    
    # نمایش variables بر اساس فایل
    declare -A file_map
    
    while IFS='|' read -r var_name file_path line_content; do
        file_map["$file_path"]+="$var_name"$'\n'
    done < "$TEMP_FILE"
    
    echo -e "${YELLOW}📋 Variables by file:${NC}"
    for file_path in "${!file_map[@]}"; do
        # گرفتن نام فایل نسبی
        rel_path=$(echo "$file_path" | sed "s|^$TARGET_DIR/||")
        echo -e "${BLUE}$rel_path${NC}"
        echo "${file_map[$file_path]}" | sort -u | sed 's/^/  - /'
        echo ""
    done
    
    # ایجاد .env.example
    echo -e "${YELLOW}📝 Creating .env.example file...${NC}"
    
    cat > "$TARGET_DIR/.env.example" << EOF
# ============================================
# Environment Variables Example
# Generated automatically on $(date)
# Project: $(basename "$TARGET_DIR")
# Type: $PROJECT_TYPE
# ============================================

# Database Configuration
EOF
    
    # متغیرهای رایج دیتابیس
    for var in DB_HOST DB_PORT DB_USER DB_PASSWORD DB_NAME DATABASE_URL MYSQL_HOST MYSQL_PORT; do
        if echo "$UNIQUE_VARS" | grep -qi "$var"; then
            echo "$var=your_${var,,}_here" >> "$TARGET_DIR/.env.example"
        fi
    done
    
    # متغیرهای امنیتی
    echo "" >> "$TARGET_DIR/.env.example"
    echo "# Security" >> "$TARGET_DIR/.env.example"
    for var in JWT_SECRET SECRET_KEY API_KEY ACCESS_TOKEN; do
        if echo "$UNIQUE_VARS" | grep -qi "$var"; then
            echo "# Change this to a strong random value!" >> "$TARGET_DIR/.env.example"
            echo "$var=your_strong_secret_here" >> "$TARGET_DIR/.env.example"
            echo "" >> "$TARGET_DIR/.env.example"
        fi
    done
    
    # سایر متغیرها
    echo "" >> "$TARGET_DIR/.env.example"
    echo "# Application Configuration" >> "$TARGET_DIR/.env.example"
    
    while IFS= read -r var; do
        # اگر قبلاً اضافه نشده
        if ! grep -q "^$var=" "$TARGET_DIR/.env.example" 2>/dev/null; then
            if [[ "$var" =~ PORT ]]; then
                echo "$var=3000" >> "$TARGET_DIR/.env.example"
            elif [[ "$var" =~ HOST|URL ]]; then
                echo "$var=http://localhost:3000" >> "$TARGET_DIR/.env.example"
            elif [[ "$var" =~ DEBUG|LOG ]]; then
                echo "$var=true" >> "$TARGET_DIR/.env.example"
            elif [[ "$var" =~ NODE_ENV ]]; then
                echo "# NODE_ENV=production" >> "$TARGET_DIR/.env.example"
                echo "NODE_ENV=development" >> "$TARGET_DIR/.env.example"
            elif [[ ! "$var" =~ ^(DB_|DATABASE|JWT|SECRET|API_KEY|ACCESS_TOKEN) ]]; then
                echo "$var=your_${var,,}_value" >> "$TARGET_DIR/.env.example"
            fi
        fi
    done <<< "$UNIQUE_VARS"
    
    # دستورالعمل‌ها
    cat >> "$TARGET_DIR/.env.example" << EOF

# ============================================
# INSTRUCTIONS:
# 1. Copy this file to .env (production) or .env.local (development)
# 2. Fill in actual values
# 3. Never commit .env files to git!
# 
# Example for development:
#   cp .env.example .env.local
#   nano .env.local
# 
# Example for production:
#   cp .env.example .env
#   nano .env
# ============================================
EOF
    
    echo -e "${GREEN}✅ Created: $TARGET_DIR/.env.example${NC}"
    
    # نمایش خلاصه
    echo ""
    echo -e "${YELLOW}📊 Summary:${NC}"
    echo "  - Unique variables: $VAR_COUNT"
    echo "  - Files scanned: ${#file_map[@]}"
    echo "  - .env.example created successfully"
    
else
    echo -e "${YELLOW}⚠️  No environment variables found${NC}"
    
    # ایجاد .env.example پیش‌فرض
    cat > "$TARGET_DIR/.env.example" << EOF
# ============================================
# Environment Variables Example
# Generated automatically on $(date)
# Project: $(basename "$TARGET_DIR")
# Type: $PROJECT_TYPE
# ============================================

# Database
DB_HOST=localhost
DB_PORT=3306
DB_USER=your_username
DB_PASSWORD=your_password
DB_NAME=your_database

# Application
PORT=3000
NODE_ENV=development
JWT_SECRET=your_jwt_secret_here

# API
API_URL=http://localhost:3000

# ============================================
# INSTRUCTIONS:
# 1. Copy this file to .env (production) or .env.local (development)
# 2. Fill in actual values
# 3. Never commit .env files to git!
# ============================================
EOF
    
    echo -e "${GREEN}✅ Created default .env.example${NC}"
fi

# پاکسازی
rm -f "$TEMP_FILE" 2>/dev/null

echo ""
echo -e "${PURPLE}===================================${NC}"
echo -e "${GREEN}🎉 Done!${NC}"

